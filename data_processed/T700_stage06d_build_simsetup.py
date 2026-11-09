"""Rebuild a source-traceable T700 SimSetup directory; never modify user models.

Run with F:/Program Files/python.exe. The installed T-MATS C gas-property source
is replayed for preprocessing. The resulting .m setup files contain literal maps.
Native libmat/libmx write/read the accompanying parameter MAT-file without
starting or licensing a MATLAB engine. Simulink runtime validation is separate.
"""
from __future__ import annotations
import csv,hashlib,json,re,struct,zlib
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from T700_stage06c_build_outputs import MatFileAPI
from t700_thermo_compressor import ThermoTMATS,build_compressor,build_compressor_extended
from t700_turbine_builder import build_turbines

ROOT=Path(__file__).resolve().parent.parent
SETUP=ROOT/'model'/'SimSetup_T700'
OUT=ROOT/'results'/'simsetup_t700'
PROCESSED=ROOT/'data_processed'


def plain(v):
    if isinstance(v,np.ndarray):return plain(v.tolist())
    if isinstance(v,np.generic):return v.item()
    if isinstance(v,dict):return {str(k):plain(x) for k,x in v.items()}
    if isinstance(v,(list,tuple)):return [plain(x) for x in v]
    return v


def element(b,o=0):
    t,n=struct.unpack_from('<II',b,o)
    if t>>16:return t&65535,b[o+4:o+4+(t>>16)],o+8
    end=o+8+n
    return t,b[o+8:end],end if t==15 else (end+7)//8*8


def numeric_matrix(b):
    _,flags,o=element(b);cl=struct.unpack_from('<I',flags)[0]&255
    _,dims,o=element(b,o);shape=struct.unpack('<'+'i'*(len(dims)//4),dims)
    _,name,o=element(b,o)
    if cl==2:
        _,size,o=element(b,o);width=struct.unpack('<i',size)[0]
        _,fnames,o=element(b,o)
        names=[fnames[i:i+width].split(b'\0',1)[0].decode() for i in range(0,len(fnames),width)]
        result={}
        for key in names:
            t,v,o=element(b,o);result[key]=numeric_matrix(v) if t==14 else None
        return result
    if cl in (1,3,17):return None # MCOS/table metadata are not needed to read selected pixels.
    t,v,o=element(b,o)
    if cl==4:
        encoding={16:'utf-8',17:'utf-16le',18:'utf-32le',4:'utf-16le',2:'latin1',1:'latin1'}[t]
        return v.decode(encoding)
    types={1:'i1',2:'u1',3:'<i2',4:'<u2',5:'<i4',6:'<u4',7:'<f4',9:'<f8',12:'<i8',13:'<u8'}
    return np.frombuffer(v,dtype=types[t]).reshape(shape,order='F').copy()


def read_selected_line(file):
    b=file.read_bytes();t,v,_=element(b,128)
    if t==15:t,v,_=element(zlib.decompress(v))
    r=numeric_matrix(v);p=r['SelectedPixels'];h=r['PixelToDataMatrix']
    xy=np.column_stack([p,np.ones(6)])@h
    return dict(nc_percent=int(re.search(r'N(\d+)_',file.name)[1]),
                PRstatic=xy[:,0],Wc=xy[:,1],SourceFile=str(file),SelectedPixels=p)


def numeric_table(script,name):
    text=script.read_text(encoding='utf-8-sig')
    body=re.search(r'T700raw\.'+name+r'\s*=\s*array2table\(\[(.*?)\]',text,re.S)[1]
    return np.array([[float(x) for x in row.split()] for row in body.splitlines() if row.strip()])


def matvalue(value):
    if isinstance(value,(bool,np.bool_)):return 'true' if value else 'false'
    if isinstance(value,str):return "'"+value.replace("'","''")+"'"
    a=np.asarray(value)
    if a.ndim==0:return format(float(a),'.17g')
    if a.ndim==1:return '['+' '.join(format(float(v),'.17g') for v in a)+']'
    return '[ ...\n'+'; ...\n'.join('    '+' '.join(format(float(v),'.17g') for v in row) for row in a)+'];'


def assignment(field,value):
    v=matvalue(value)
    return field+' = '+v+('' if v.endswith(';') else ';')+'\n'


def write_setup(name,body,description):
    text=f'function MWS = {name}(MWS)\n% {description}\n% Generated from local Ballin data; see README_T700.txt and build audit.\n\n'+body+'\nend\n'
    (SETUP/(name+'.m')).write_text(text,encoding='utf-8')


def row_interp(table,x,axis):
    a=np.asarray(table,float);return np.array([np.interp(x,axis,a[:,j]) for j in range(a.shape[1])])


def reference_from_maps(hpc,curves,c,thermo):
    nc=c['TrimNg']/np.sqrt(c['TrimT2']/c['Tstd'])/c['NgDesign']
    pr=c['TrimPs3']/c['Kps3']/c['TrimP2']
    prrow=row_interp(hpc['PRArray'],nc,hpc['NcVec'])
    rline=np.interp(pr,prrow[::-1],np.asarray(hpc['RlineVec'])[::-1])
    wc=np.interp(rline,hpc['RlineVec'],row_interp(hpc['WcArray'],nc,hpc['NcVec']))
    w=wc*c['TrimP2']/c['Pstd']/np.sqrt(c['TrimT2']/c['Tstd'])
    ps=c['TrimPs3']/c['TrimP2']
    a2=np.array(curves['A02']['points']);tau=np.interp(ps,a2[:,0],a2[:,1]);t3=c['TrimT2']*tau
    h2=float(thermo.t2h(c['TrimT2'],0));h3=float(thermo.t2h(t3,0))
    # Translate the source empirical effective bleed enthalpy through its T(h)
    # relation before using T-MATS' different absolute enthalpy reference.
    ballin_h3=c['KH31']*t3+c['KH32']
    t_mid=(c['KQc1']*ballin_h3-c['KH32'])/c['KH31']
    h_mid=float(thermo.t2h(t_mid,0))
    hfrac=(h_mid-h2)/(h3-h2)
    assert 0<=hfrac<=1
    values={}
    for key,q in [('A03',nc*100),('A04',wc),('A05',wc),('A10',nc*100)]:
        p=np.array(curves[key]['points']);y=p[:,1].copy()
        if key=='A03':y[abs(y)<=p[:,3]]=0 # visible zero plateau, within raster resolution.
        values[key]=float(np.interp(q,p[:,0],y))
    b1,b2,b3=values['A03'],values['A04'],values['A05']
    fractions=np.array([b1+b2,b3*(1-c['Kbl'])+c['Kb3'],b3*c['Kbl']])
    assert fractions.min()>=0 and fractions.sum()<1
    return dict(NGc=nc,Rline=rline,InletFlow=w,CorrectedFlow=wc,T3_R=t3,
                MidBleedTemperature_R=t_mid,MidBleedEnthalpyFraction=hfrac,
                B1=b1,B2=b2,B3=b3,BleedFractions=fractions,
                BleedEnthalpyFractions=np.array([hfrac,1.,1.]),
                # Pressure of discarded intermediate bleed is not provided.
                BleedPressureFractions=np.array([.5,1.,1.]),
                f10Ref=values['A10'],CoolingReturn_lbm_s=w*fractions[2],
                GGTMainFlowEstimate_lbm_s=w*(1-fractions.sum())+c['TrimWf_lbm_h']/3600)


def emit_files(params,constants,ref):
    SETUP.mkdir(parents=True,exist_ok=True)
    for name,group in [('setup_T700_HPC','HPC'),('setup_T700_HPT','HPT'),('setup_T700_FPT','FPT')]:
        source=params[group];body=''
        for k in ('NcVec','RlineVec','PRVec','s_Nc','s_Wc','s_PR','s_eff'):
            if k in source:body+=assignment(f'MWS.{group}.{k}',source[k])
        for k in ('WcArray','PRArray','EffArray'):
            if k not in source:continue
            a=np.asarray(source[k])
            if group!='HPC':
                body+=f'% Nc rows are replicated interface rows, not measured speed curves.\n'
                body+=f'MWS.{group}.{k} = repmat('+matvalue(a[0])+f',numel(MWS.{group}.NcVec),1);\n'
            else:body+=assignment(f'MWS.{group}.{k}',a)
        if group=='HPC':
            for k in ('WcMapSurge','PRMapSurge','BleedFractions','BleedEnthalpyFractions','BleedPressureFractions'):
                body+=assignment(f'MWS.HPC.{k}',source[k])
            for k in ('BleedFractions','BleedEnthalpyFractions','BleedPressureFractions'):
                body+=f'MWS.HPC.{k} = MWS.HPC.{k}(:);\n'
            body+="MWS.HPC.SurgeLineValidated = false;\nMWS.HPC.LowPRPlateauIsApproximation = true;\n"
        body+=f"MWS.{group}.Meta = jsondecode(MWS.T700.{group}.MetadataJSON);\n"
        write_setup(name,body,f'{group} reference-condition adapter, ordinary T-MATS off-design format.')
    body=''.join(assignment('MWS.Burner.'+k,v) for k,v in params['Burner'].items() if isinstance(v,(int,float,bool,str)))
    write_setup('setup_T700_Burner',body,'Burner source efficiency/LHV; pressure loss frozen at Appendix-B trim 1.')
    write_setup('setup_T700_Shaft',assignment('MWS.Shaft.Jg',constants['Jg'])+
                assignment('MWS.Shaft.Jp',constants['Jp'])+
                'MWS.Shaft.Jload = 0; % No external rotor/load inertia has been specified.\n',
                'Shaft inertia in slug*ft^2; source ft*lbf*s^2 has the same numerical value.')
    write_setup('setup_T700_source_functions',
                "setupRoot = fileparts(mfilename('fullpath'));\nS = load(fullfile(setupRoot,'T700_parameter_bundle.mat'),'T700Parameters');\nMWS.T700 = S.T700Parameters;\n",
                'Load traceable source-function data and construction metadata.')

    # The rest is small executable glue; component arrays above remain explicit.
    write_setup('setup_T700_Solver',
                "MWS.Solve.C_Lim = [1e-6;1e-6;1e-6;1e-6;0.05;0.05];\n"
                "MWS.Solve.J_Calc_Per = [0.005*ones(1,6);-0.005*ones(1,6)];\n"
                "MWS.Solve.NR_IC = MWS.T700.Reference.XSeed(:);\n"
                "MWS.Solve.NR_dx = 5; % Update limit: 5 percent, not an iteration count.\n"
                "MWS.Solve.NR_Jac_Re = 20;\nMWS.Solve.T = 0.015;\n"
                "ngBounds = MWS.HPC.s_Nc*[min(MWS.HPC.NcVec);max(MWS.HPC.NcVec)]*sqrt(MWS.Boundary.T2_R/MWS.T700.Constants.Tstd);\n"
                "MWS.Solve.Lower = [1;min(MWS.HPC.RlineVec);min(MWS.HPT.PRVec);min(MWS.FPT.PRVec);ngBounds(1);5000];\n"
                "MWS.Solve.Upper = [15;max(MWS.HPC.RlineVec);max(MWS.HPT.PRVec);max(MWS.FPT.PRVec);ngBounds(2);1.2*MWS.T700.Constants.NpDesign];\n"
                "MWS.Solve.NR_IC = min(MWS.Solve.Upper,max(MWS.Solve.Lower,MWS.Solve.NR_IC));\n"
                "MWS.Solve.UnknownOrder = {'W_in','Rline','PR_GGT','PR_FPT','Ng','Np'};\n"
                "MWS.Solve.ResidualOrder = {'P49_error','Compressor_flow','GGT_flow','FPT_flow','Ng_dot_rpm_s','Np_dot_rpm_s'};\n",
                'Six physical unknowns; the last two residual tolerances have rpm/s units.')

    boundary="""function MWS = setup_T700_boundary(MWS,profile,caseID)
% Select boundary data without adapting maps to experimental outputs.
C = MWS.T700.Constants;
if strcmpi(profile,'ballin_trim1')
    MWS.Boundary.P2_psia = C.TrimP2;
    MWS.Boundary.T2_R = C.TrimT2;
    MWS.Boundary.P49_psia = MWS.T700.Reference.P49_psia;
    MWS.Boundary.Wf = C.TrimWf_lbm_h/3600;
    MWS.Boundary.Qload = C.TrimQload;
    MWS.Boundary.CaseID = 0;
    MWS.Boundary.Source = 'Ballin_public_reference_trim1';
elseif strcmpi(profile,'lewis')
    assert(isscalar(caseID) && ismember(caseID,1:6),'CaseID must be 1..6.');
    R = MWS.Reference.Input(MWS.Reference.Input.CaseID==caseID,:);
    MWS.Boundary.P2_psia = R.P2_psia;
    MWS.Boundary.T2_R = R.T2_R;
    MWS.Boundary.P49_psia = R.P49_psia;
    MWS.Boundary.Wf = R.Wf_lb_s;
    MWS.Boundary.Qload = R.Qload_lbf_ft;
    MWS.Boundary.CaseID = caseID;
    MWS.Boundary.Source = 'NASA_Lewis_test_article_unadapted_reference_maps';
else
    error('Profile must be ballin_trim1 or lewis.');
end
MWS.Boundary.FAR2 = 0;
MWS.Boundary.Pacc_g = 0;
MWS.Boundary.Pacc_p = 0;
MWS.Boundary.Alt = 0;
MWS.Boundary.dTamb = 0;
MWS.Boundary.Mach = 0;
MWS.Boundary.Profile = profile;
MWS.Boundary.OutletTotalPressurePrescribed = true;
MWS.Boundary.ExhaustFactorAlsoImposed = false;
end
"""
    (SETUP/'setup_T700_boundary.m').write_text(boundary,encoding='utf-8')
    all_code="""function MWS = T700_setup_all(profile,caseID)
% Complete source-traceable parameter initialization; does not open/run a model.
if nargin<1, profile='ballin_trim1'; end
if nargin<2, caseID=4; end
setupRoot = fileparts(mfilename('fullpath'));
projectRoot = fileparts(fileparts(setupRoot));
addpath(setupRoot,'-begin');
MWS = struct;
MWS.engName = 'T700_reference_adapter';
MWS.top_level = fileparts(setupRoot);
MWS = setup_T700_source_functions(MWS);
D = MWS.T700.Experimental;
MWS.Reference.Source.Report = 'NASA-TM-83579, Tables I/II';
MWS.Reference.Source.Engine = 'NASA Lewis experimental test article';
MWS.Reference.Input = array2table(D.InputNumeric,'VariableNames', ...
    {'CaseID','P2_psia','T2_R','P49_psia','Qload_lbf_ft','Wf_lb_h'});
MWS.Reference.Input.Wf_lb_s = MWS.Reference.Input.Wf_lb_h/3600;
MWS.Reference.Reference = array2table(D.MeasuredNumeric,'VariableNames', ...
    {'CaseID','Ng_rpm','Np_rpm','WA2_lb_s','P3_psia','T3_R','T45_R','T49_R'});
MWS = setup_T700_HPC(MWS);
MWS = setup_T700_HPT(MWS);
MWS = setup_T700_FPT(MWS);
MWS = setup_T700_Burner(MWS);
MWS = setup_T700_Shaft(MWS);
MWS = setup_T700_boundary(MWS,profile,caseID);
MWS = setup_T700_Solver(MWS);
MWS.in.SimTime = 1.5; % Time steps are not an asserted NR iteration count.
MWS.Inlet.eRambase = 1; % The SS adapter uses the prescribed inlet gas bus.
MWS.Duct.dP = 0; % The SS adapter bypasses the old exhaust duct/nozzle.
MWS.Input.NRICDyn = nan(4,1);
MWS.Input.Ng0 = NaN;
MWS.Input.Np0 = NaN;
MWS.Input.LP_Shaft = NaN;
MWS.Input.FARin = NaN;
MWS.Project.Root = projectRoot;
MWS.Project.SetupRoot = setupRoot;
MWS.Project.ParametersGenerated = true;
MWS.Project.DataPackageLoaded = true;
MWS.Project.MapAdapterLoaded = true;
MWS.Project.T700ParametersApplied = false; % Requires model-interface audit.
MWS.Project.SSInterfacesReady = false;
MWS.Project.SteadyConvergenceVerified = false;
MWS.Project.ExperimentalValidated = false;
MWS.Project.DynamicTrimReady = false;
MWS.Project.BleedScheduleMode = 'frozen_AppendixB_trim1';
MWS.Project.MapsAreReferenceConditionApproximation = true;
MWS.Project.AllSourcePhenomenaImplementedExactly = false;
names = {'setup_T700_source_functions';'setup_T700_HPC';'setup_T700_HPT'; ...
    'setup_T700_FPT';'setup_T700_Burner';'setup_T700_Shaft'; ...
    'setup_T700_boundary';'setup_T700_Solver'};
files = cell(size(names));
for k=1:numel(names)
    files{k}=which(names{k});
    assert(strcmpi(files{k},fullfile(setupRoot,[names{k} '.m'])),'Wrong setup source: %s',names{k});
end
MWS.Project.SetupFiles = table(names,files,'VariableNames',{'Function','File'});
end
"""
    (SETUP/'T700_setup_all.m').write_text(all_code,encoding='utf-8')
    init="""function MWS = T700_initialize_from_data(profile,caseID)
% Entry point for SimSetup_T700; isolated from the legacy initializer.
if nargin<1, profile='ballin_trim1'; end
if nargin<2, caseID=4; end
modelDir = fileparts(mfilename('fullpath'));
setupRoot = fullfile(modelDir,'SimSetup_T700');
addpath(modelDir,'-begin'); addpath(setupRoot,'-begin');
assert(strcmpi(which('T700_setup_all'),fullfile(setupRoot,'T700_setup_all.m')));
MWS = T700_setup_all(profile,caseID);
assignin('base','MWS',MWS);
end
"""
    (ROOT/'model'/'T700_initialize_from_data.m').write_text(init,encoding='utf-8')


def main():
    if (ROOT/'model'/'SimSetup_T700'/'setup_T700_Compressor.m').is_file() or ((ROOT/'model'/'SimSetup'/'setup_T700_HPC.m').is_file() and not (SETUP/'T700_setup_all.m').is_file()):
        raise RuntimeError('Historical builder retired after unified T700_initialize migration. Do not recreate old entries; see results/simsetup_t700/README_current_layout.txt.')
    SETUP.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
    curve_dir=ROOT/'data_raw'/'component_functions'
    curves={f'A{i:02d}':json.loads((curve_dir/f'T700_A{i:02d}_raw.json').read_text()) for i in range(2,12)}
    line_files=sorted((ROOT/'data_raw'/'compressor').glob('T700_compressor_A1_N???_raw.mat'))
    lines=[read_selected_line(p) for p in line_files];assert len(lines)==11
    script=PROCESSED/'T700_experimental_data_preparation.m'
    inputs=numeric_table(script,'Input'); measured=numeric_table(script,'Measured')
    c=dict(Tstd=518.67,Pstd=14.695951,Kps3=.956,NgDesign=44700.,NpDesign=20900.,
           TrimNg=41638.,TrimNp=20895.,TrimT2=518.67,TrimP2=14.696,
           TrimPs3=176.34,TrimT41=2292.,TrimT45=1632.,TrimP41=174.28,
           TrimP45=37.42,TrimWf_lbm_h=476.3,TrimQload=229.,
           Jg=.0445,Jp=.062,LHV=18300.,KWGT=.0876,KTH_a=.0018326,KTH_b=.0856,
           Kbl=.7826,Kb3=.0025,Kdpb=.03045,KQc1=.71,KQc2=.29,
           KH31=.2496,KH32=-8.4,KH45=.9623,FPTMinimumPR=1.25,
           FPTFARref=.017030162009300538)
    c['LewisCases']=[dict(CaseID=int(i[0]),P2_psia=i[1],T2_R=i[2],P3_psia=m[4],Ng_rpm=m[1])
                     for i,m in zip(inputs,measured)]
    thermo=ThermoTMATS()
    strict,strict_check=build_compressor(lines,curves['A02'],thermo,c)
    hpc,hpc_check=build_compressor_extended(lines,curves['A02'],thermo,c)
    hpt,fpt,turbine_check=build_turbines(curves,thermo,c)
    ref=reference_from_maps(hpc,curves,c,thermo)
    for key in ('BleedFractions','BleedEnthalpyFractions','BleedPressureFractions'):hpc[key]=ref[key]
    burn=dict(Eff=float(np.mean(np.array(curves['A06']['points'])[:,1])),LHV=c['LHV'],
              dP=1-c['TrimP41']/(c['TrimPs3']/c['Kps3']),
              PressureLossMode='frozen_AppendixB_trim1',EfficiencyMode='A6_constant_mean')
    xseed=np.array([ref['InletFlow'],ref['Rline'],c['TrimP41']/c['TrimP45'],
                    c['TrimP45']/(c['Pstd']*ref['f10Ref']),c['TrimNg'],c['TrimNp']])
    ref['XSeed']=xseed;ref['P49_psia']=c['Pstd']*ref['f10Ref']
    funcs={}
    for key,r in curves.items():
        p=np.array(r['points']);y=p[:,1].copy()
        if key=='A03':y[abs(y)<=p[:,3]]=0
        if key=='A06':y[:]=np.mean(y)
        funcs[key]=dict(X=p[:,0],Y=y,RawY=p[:,1],Definition=r['definition'],
                        MetadataJSON=json.dumps(r,ensure_ascii=True))
    funcs['A01']=dict(NcPercent=np.array([p['nc_percent'] for p in lines]),
                       PRstatic=np.vstack([p['PRstatic'] for p in lines]),
                       Wc=np.vstack([p['Wc'] for p in lines]))
    params=dict(HPC=hpc,HPT=hpt,FPT=fpt,Burner=burn,Shaft=dict(Jg=c['Jg'],Jp=c['Jp']))
    meta=dict(Source='Ballin NASA-TM-100991 public reference, not Lewis-calibrated',
              SourceFunctionsPreserved=True,RawDataModified=False,
              BleedScheduleMode='frozen_AppendixB_trim1',
              IntermediateBleedEnthalpyMode='Ballin effective enthalpy -> source T -> T-MATS h at trim1',
              IntermediateBleedPressureFraction=.5,
              IntermediateBleedPressureIsAssumption=True,
              GGTExitCoolingMode='rear injection; actual T-MATS enthalpy mixing',
              BallinKH45NotMultipliedIntoTMATSEnthalpy=True,
              BurnerPressureLossFrozenAtReference=True,
              ExperimentalCalibrationPerformed=False,SimulinkSimulationRun=False,
              A9RatioMode='figure_ambient',A10AppliedAsLewisBoundary=False,
              LowPRPlateauIncludedAsExplicitApproximation=True,
              HPTAdapterAssumesNoCoolingForEfficiencyCalibration=True,
              FPTAdapterReferenceFARIncludesSourceCoolingDilution=True,
              Limitations=['Turbine Nc rows are replicated, not real measured speed lines.',
                           'Turbine temperature, FAR and exhaust pressure factor are frozen at documented reference values.',
                           'Bleed fractions/enthalpy fraction and burner pressure drop are frozen at reference, not live schedules.',
                           'T-MATS rear cooling mixing is not exactly the Ballin empirical absolute-enthalpy relation.',
                           'Low-PR compressor plateau amplitude/junction use the first selected short-branch point.',
                           'No valid surge-margin prediction; the high-PR edge is a proxy.',
                           'No steady/dynamic/experimental validation is implied by loading these maps.'])
    checks=dict(Compressor=hpc_check,StrictCompressor=strict_check,Turbines=turbine_check,
                Reference=ref,ConstructionMetadata=meta)
    (OUT/'T700_simsetup_construction_checks.json').write_text(json.dumps(plain(checks),indent=2,allow_nan=False),encoding='utf-8')
    (PROCESSED/'T700_adapter_numeric_parameters.json').write_text(json.dumps(plain(params),indent=2,allow_nan=False),encoding='utf-8')
    bundle=dict(Constants={k:v for k,v in c.items() if k!='LewisCases'},Reference=ref,
                Experimental=dict(InputNumeric=inputs,MeasuredNumeric=measured),
                SourceFunctions=funcs,MetadataJSON=json.dumps(plain(meta),ensure_ascii=True))
    for key,group in params.items():
        clean={k:v for k,v in group.items() if not isinstance(v,dict)}
        # Retain only MATLAB-compatible numeric/string/simple fields; detailed
        # variable-length construction records stay in the JSON audit.
        for k,v in list(clean.items()):
            if isinstance(v,list):
                try:
                    clean[k]=np.asarray(v,dtype=float)
                except (TypeError,ValueError):
                    if not all(isinstance(z,str) for z in v):del clean[k]
            elif not isinstance(v,(str,bool,int,float,np.ndarray)):
                del clean[k]
        clean['MetadataJSON']=json.dumps(plain(group),ensure_ascii=True)
        bundle[key]=clean
    api=MatFileAPI();dest=SETUP/'T700_parameter_bundle.mat'
    # Use the installed native MAT-file API; all tables are ordinary structs.
    handle=api.open(str(dest).encode('utf-8'),b'w');assert handle
    value=api.array(bundle)
    try:assert api.put(handle,b'T700Parameters',value)==0
    finally:api.destroy(value);assert api.close(handle)==0
    handle=api.open(str(dest).encode('utf-8'),b'r');root=api.get(handle,b'T700Parameters');assert root
    try:
        for group in ('HPC','HPT','FPT'):
            field=api.field(root,group)
            for name in ('WcArray','EffArray'):
                assert np.array_equal(api.read_matrix(api.field(field,name)),np.asarray(params[group][name]))
    finally:api.destroy(root);assert api.close(handle)==0
    emit_files(bundle,c,ref)
    # Component-map review figures are construction evidence, not engine tests.
    fig,axes=plt.subplots(2,2,figsize=(12,9),layout='constrained')
    for i,nc in enumerate(hpc['NcVec']):
        axes[0,0].plot(np.array(hpc['WcArray'])[i],np.array(hpc['PRArray'])[i],label=f'{100*nc:g}%')
        axes[0,1].plot(np.array(hpc['WcArray'])[i],np.array(hpc['EffArray'])[i])
    axes[0,0].set(xlabel='Standard corrected flow [lbm/s]',ylabel='Total pressure ratio',title='HPC: source short branches + explicit low-PR plateau')
    axes[0,0].legend(fontsize=7,ncol=3);axes[0,1].set(xlabel='Standard corrected flow [lbm/s]',ylabel='Efficiency',title='HPC: reference-temperature reconstructed efficiency')
    for group,ax in ((hpt,axes[1,0]),(fpt,axes[1,1])):
        ax.plot(group['PRVec'],np.array(group['WcArray'])[0],label='Wc')
        right=ax.twinx();right.plot(group['PRVec'],np.array(group['EffArray'])[0],color='tab:orange',label='Efficiency')
        ax.set(xlabel='Inlet / outlet total pressure ratio',ylabel='Standard Wc [lbm/s]')
        right.set_ylabel('Efficiency');ax.grid(alpha=.2)
    axes[1,0].set_title('GGT: repeated Nc rows; reference T/FAR')
    axes[1,1].set_title('FPT: ambient-ratio interpretation; frozen exhaust factor')
    for ax in axes.flat:ax.grid(alpha=.2)
    fig.suptitle('T700 reference-condition SimSetup adapter: construction review',fontsize=14)
    fig.savefig(OUT/'T700_simsetup_maps.png',dpi=160);plt.close(fig)
    print('HPC shape',np.shape(hpc['WcArray']),'HPT',np.shape(hpt['WcArray']),'FPT',np.shape(fpt['WcArray']))
    print('Reference bleed fractions',ref['BleedFractions'],'burner',burn)
    print('Native MAT-file API read-back: PASS')
    print('T700_SIMSETUP_PARAMETER_FILES_GENERATED')


if __name__=='__main__':main()

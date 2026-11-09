function MWS = T700_initialize(profile,caseID)
% Unified workspace initialization. Does not open, edit, or run a model.
% First no-argument call uses Ballin trim1; later no-argument callbacks retain
% the explicitly selected profile in this project's base-workspace MWS.
% T700_initialize('ballin_trim1') / ('ballin_trim2') / ('ballin_trim3')
% T700_initialize('lewis',4)      -> Lewis experimental input case 4
modelDir=fileparts(mfilename('fullpath'));
projectRoot=fileparts(modelDir);
if nargin<1 || isempty(profile)
    profile='ballin_trim1'; caseID=[];
    if evalin('base','exist(''MWS'',''var'')')==1
        previous=evalin('base','MWS');
        if isstruct(previous) && isfield(previous,'Project') && ...
                isfield(previous.Project,'Root') && strcmpi(previous.Project.Root,projectRoot) && ...
                isfield(previous,'Boundary') && isfield(previous.Boundary,'Profile')
            profile=previous.Boundary.Profile;
            if strcmpi(profile,'lewis'), caseID=previous.Boundary.CaseID; end
        end
    end
elseif nargin<2
    caseID=[];
end
profile=char(string(profile));
if strcmpi(profile,'lewis')
    validateattributes(caseID,{'numeric'},{'scalar','integer','>=',1,'<=',6});
elseif ismember(lower(profile),{'ballin_trim1','ballin_trim2','ballin_trim3'})
    assert(isempty(caseID),'Ballin 工况不使用 Lewis CaseID，请省略第二个参数。');
else
    error('工况模式必须为 ballin_trim1/2/3 或 lewis。');
end
setupRoot=fullfile(modelDir,'SimSetup_T700');
addpath(modelDir,'-begin');
addpath(setupRoot,'-begin');
steadyRoot=fullfile(modelDir,'SteadyState');
assert(isfolder(steadyRoot),'缺少稳态脚本目录 SteadyState。');
addpath(steadyRoot,'-begin');
dataFile=fullfile(projectRoot,'data_processed','T700_parameter_bundle.mat');
S=load(dataFile,'T700Parameters');
P=S.T700Parameters;
MWS=struct;
MWS.engName='T700_reference_adapter';
MWS.top_level=modelDir;
% Runtime constants, required schedules, reference seed and metadata enter MWS.
% Measured experimental outputs and unused source functions stay in the MAT file.
MWS.T700.Constants=P.Constants;
MWS.T700.Reference=P.Reference;
MWS.T700.Compressor.MetadataJSON=P.Compressor.MetadataJSON;
MWS.T700.GGT.MetadataJSON=P.GGT.MetadataJSON;
MWS.T700.FPT.MetadataJSON=P.FPT.MetadataJSON;
MWS.T700.Exhaust.NGcPercent=P.SourceFunctions.A10.X(:);
MWS.T700.Exhaust.Factor=P.SourceFunctions.A10.Y(:);
MWS.T700.Exhaust.Interpretation='P49/Ps9 according to Eq38; A10 ordinate prints inverse ratio';
MWS.T700.FPTFlowInterpretation='A9 figure Ps9/P45; Eq33 differs; frozen f10 adapter retained';
MWS.Reference.Source.Report='NASA-TM-83579, Table I';
MWS.Reference.Source.Engine='NASA Lewis experimental test article';
MWS.Reference.Input=array2table(P.Experimental.InputNumeric,'VariableNames', ...
    {'CaseID','P2_psia','T2_R','P49_psia','Qload_lbf_ft','Wf_lb_h'});
MWS.Reference.Input.Wf_lb_s=MWS.Reference.Input.Wf_lb_h/3600;
% Source Table B.1, PDF67 / printed53. These are source-model trim targets,
% not independent experimental data. Shaft torque is referenced to engine shaft.
MWS.Reference.Ballin=array2table([ ...
    1 41638 20895 476.3 229.0 14.696 518.67 176.34 174.28 37.42 2292 1632 911.1; ...
    2 39768 20895 349.3 138.9 14.696 518.67 142.13 140.26 30.66 2102 1501 552.6; ...
    3 38072 20895 267.7  76.06 14.696 518.67 114.27 112.77 25.54 1982 1424 302.6], ...
    'VariableNames',{'TrimID','Ng_rpm','Np_rpm','Wf_lb_h','Qload_lbf_ft', ...
    'P2_psia','T2_R','Ps3_psia','P41_psia','P45_psia','T41_R','T45_R','Power_hp'});
MWS=setup_T700_Compressor(MWS,P.SourceFunctions);
MWS=setup_T700_GGT(MWS);
MWS=setup_T700_FPT(MWS);
MWS=setup_T700_Burner(MWS);
MWS=setup_T700_Shaft(MWS);
MWS=setup_T700_Shaft1(MWS);
MWS=setup_T700_Inlet(MWS);
MWS=setup_T700_Duct(MWS);
MWS=setup_T700_Nozzle(MWS);
MWS=setup_T700_boundary(MWS,profile,caseID);
% Solver settings belong to the initialization entry, not a component file.
MWS.Solve.C_Lim = [1e-6;1e-6;1e-6;1e-6;0.05;0.05];
MWS.Solve.J_Calc_Per = [0.005*ones(1,6);-0.005*ones(1,6)];
MWS.Solve.NR_IC = MWS.T700.Reference.XSeed(:);
if startsWith(lower(profile),'ballin_trim')
    ref=MWS.Reference.Ballin(MWS.Reference.Ballin.TrimID==MWS.Boundary.TrimID,:);
    nc=ref.Ng_rpm/sqrt(ref.T2_R/MWS.T700.Constants.Tstd)/MWS.Compressor.s_Nc;
    pr=1+(ref.Ps3_psia/MWS.T700.Constants.Kps3/ref.P2_psia-1)/MWS.Compressor.s_PR;
    prRow=interp1(MWS.Compressor.NcVec,MWS.Compressor.PRArray,nc,'linear');
    rline=interp1(fliplr(prRow),fliplr(MWS.Compressor.RlineVec),pr,'linear');
    wcRow=interp1(MWS.Compressor.NcVec,MWS.Compressor.WcArray,nc,'linear');
    wc=interp1(MWS.Compressor.RlineVec,wcRow,rline,'linear')*MWS.Compressor.s_Wc;
    w=wc*(ref.P2_psia/MWS.T700.Constants.Pstd)/sqrt(ref.T2_R/MWS.T700.Constants.Tstd);
    MWS.Solve.NR_IC=[w;rline;ref.P41_psia/ref.P45_psia; ...
        ref.P45_psia/MWS.Boundary.P49_psia;ref.Ng_rpm;ref.Np_rpm];
    assert(all(isfinite(MWS.Solve.NR_IC)),'Ballin 参考初值超出特性图覆盖范围。');
end
MWS.Solve.NR_dx = 5; % Update limit: 5 percent, not an iteration count.
MWS.Solve.NR_Jac_Re = 20;
MWS.Solve.T = 0.015;
ngBounds = MWS.Compressor.s_Nc*[min(MWS.Compressor.NcVec);max(MWS.Compressor.NcVec)]*sqrt(MWS.Boundary.T2_R/MWS.T700.Constants.Tstd);
MWS.Solve.Lower = [1;min(MWS.Compressor.RlineVec);min(MWS.GGT.PRVec);min(MWS.FPT.PRVec);ngBounds(1);5000];
MWS.Solve.Upper = [15;max(MWS.Compressor.RlineVec);max(MWS.GGT.PRVec);max(MWS.FPT.PRVec);ngBounds(2);1.2*MWS.T700.Constants.NpDesign];
MWS.Solve.NR_IC = min(MWS.Solve.Upper,max(MWS.Solve.Lower,MWS.Solve.NR_IC));
MWS.Solve.UnknownOrder = {'W_in','Rline','PR_GGT','PR_FPT','Ng','Np'};
MWS.Solve.ResidualOrder = {'P49_error','Compressor_flow','GGT_flow','FPT_flow','Ng_dot_rpm_s','Np_dot_rpm_s'};


MWS.in.SimTime = 1.5; % Time steps are not an asserted NR iteration count.
MWS.Input.NRICDyn = nan(4,1);
MWS.Input.Ng0 = NaN;
MWS.Input.Np0 = NaN;
MWS.Input.LP_Shaft = NaN;
MWS.Input.FARin = NaN;
MWS.Project.Root = projectRoot;
MWS.Project.SetupRoot = setupRoot;
MWS.Project.SteadyScriptRoot = steadyRoot;
MWS.Project.SteadyResultRoot = fullfile(steadyRoot,'results');
MWS.Project.ParametersGenerated = true;
MWS.Project.DataPackageLoaded = true;
MWS.Project.MapAdapterLoaded = true;
MWS.Project.T700ParametersApplied = false; % Requires model-interface audit.
MWS.Project.SSInterfacesReady = false;
MWS.Project.SteadyConvergenceVerified = false;
MWS.Project.ExperimentalValidated = false;
MWS.Project.DynamicTrimReady = false;
MWS.Project.NozzleParametersReady = false;
MWS.Project.BleedScheduleMode = 'state_dependent_A3_A5';
% Initialization does not inspect model connections. Empty means not checked,
% not a disconnected interface. Use T700_SS_check_model for current evidence.
MWS.Project.BleedDemandInterfaceVerified=[];
MWS.Project.BleedDemandInterfaceStatus='not_checked_by_initializer';
MWS.Project.MapsAreReferenceConditionApproximation = true;
MWS.Project.AllSourcePhenomenaImplementedExactly = false;
MWS.Project.FixedParameterReferenceTrim=1;
MWS.Project.SourcePressureRatioAmbiguityResolved=false;

names={'setup_T700_Compressor';'setup_T700_GGT';'setup_T700_FPT'; ...
    'setup_T700_Burner';'setup_T700_Shaft';'setup_T700_Shaft1'; ...
    'setup_T700_Inlet';'setup_T700_Duct';'setup_T700_Nozzle';'setup_T700_boundary'};
files=cell(size(names));
for k=1:numel(names)
    files{k}=which(names{k});
    assert(strcmpi(files{k},fullfile(setupRoot,[names{k} '.m'])),'参数设置函数来源不符：%s',names{k});
end
MWS.Project.SetupFiles=table(names,files,'VariableNames',{'Function','File'});
MWS.Project.ParameterBundle=dataFile;
MWS.Project.ExperimentalMeasurementsLoaded=false;
assert(strcmpi(which('T700_check_parameters'),fullfile(modelDir,'T700_check_parameters.m')));
T700_check_parameters(MWS);
MWS.Project.ParameterChecksPassed=true;
assignin('base','MWS',MWS);
fprintf('T700 工作区已初始化，工况：%s。本次仅加载参数，未修改模型或运行仿真。\n',profile);
end

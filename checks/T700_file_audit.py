"""Static audit of active model references, setup files and logging contracts.

Does not load/compile/simulate Simulink. Run with an ordinary Python runtime.
"""
from pathlib import Path
import re,json,xml.etree.ElementTree as E,hashlib
ROOT=Path(__file__).resolve().parent.parent

def package_parts(s):
    result={}
    for m in re.finditer(r'__MWOPC_PART_BEGIN__ ([^\r\n]+)\r?\n(.*?)(?=__MWOPC_PART_BEGIN__|__MWOPC_PACKAGE_END__|\Z)',s,re.S):
        if m[1].endswith(('.xml','.rels')):result[m[1]]=E.fromstring(m[2].strip())
    return result

def main():
    model=ROOT/'model'
    setup=model/'SimSetup_T700'
    providers=[model/'T700_initialize.m',*setup.glob('*.m')]
    code='\n'.join(p.read_text(encoding='utf-8') for p in providers)
    assigned=set(re.findall(r'\b(MWS\.[A-Za-z0-9_.]+)\s*=',code))
    report=dict(StaticAuditOnly=True,CompilationPerformed=False,SimulationRun=False,Models={})
    expected={'Compressor':('WcArray','PRArray','EffArray','NcVec','RlineVec'),
              'GGT':('WcArray','EffArray','NcVec','PRVec'),
              'FPT':('WcArray','EffArray','NcVec','PRVec')}
    for component,fields in expected.items():
        assert (setup/f'setup_T700_{component}.m').is_file()
        for field in fields:assert f'MWS.{component}.{field}' in assigned
    for p in [*model.glob('T700*.m'),*setup.glob('*.m'),*(ROOT/'checks').glob('*.m')]:
        s=p.read_text(encoding='utf-8')
        assert not re.search(r'\bMWS\.(HPC|HPT|HTC|Noz)\b',s),p
        match=re.search(r'^function\s+(?:\[[^]]*\]\s*=\s*|\w+\s*=\s*)?(\w+)',s,re.M)
        if match:assert match[1]==p.stem,(p,match[1])
    for name in ('T700_SS','T700_Dyn'):
        path=model/f'{name}.mdl';s=path.read_text(encoding='utf-8')
        parts=package_parts(s)
        refs=sorted(set(re.findall(r'\bMWS\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+',s)))
        missing=[ref for ref in refs if ref not in assigned]
        assert not missing,(name,missing)
        logs=[];components=[]
        for part,tree in parts.items():
            if not part.startswith('/simulink/systems/'):continue
            for b in tree.findall('Block'):
                ps={p.get('Name'):p.text for p in b.findall('P')}
                if b.get('BlockType')=='ToWorkspace':logs.append(dict(Part=part,Variable=ps.get('VariableName'),Commented=ps.get('Commented','off'),SaveFormat=ps.get('SaveFormat')))
                if ps.get('SourceBlock','').startswith('Lib_Turbo_'):
                    ip={p.get('Name'):p.text for p in b.findall('InstanceData/P')}
                    components.append(dict(Part=part,Name=b.get('Name'),Commented=ps.get('Commented','off'),Parameters={k:v for k,v in ip.items() if v and v.startswith('MWS.')}))
        report['Models'][name]=dict(SHA256=hashlib.sha256(path.read_bytes()).hexdigest(),XMLPartsParsed=len(parts),ReferencedWorkspaceFields=len(refs),MissingFields=missing,Components=components,Logs=logs)
    report['KnownPendingItems']=[
        "PlotSSData.m was retired after plot merge. User must replace the four plot-button OpenFcn calls with PlotData('ss') / PlotData('dyn').",
        'Nozzle fields exist only as explicit NaN/empty placeholders; active Dyn nozzle is not ready.',
        'Dyn trim values remain NaN and both outer integrators still share the old initial-value expression.',
        'Dyn solver/control/boundary topology is still the user-maintained original layout.',
        'Compressor bleed and turbine cooling switches remain off; renamed maps alone do not implement source cooling.',
        'SS and Dyn logging wiring is unchanged. PlotData maps s4/S4 to S41, s5/S5 to S45, s6/S6 to S49.',
        'File parsing and workspace-field coverage do not prove a model can compile or converge.'
    ]
    target=ROOT/'results'/'simsetup_t700'/'T700_active_file_audit.json'
    target.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('T700_ACTIVE_STATIC_FILE_AUDIT_PASSED')
    for name,v in report['Models'].items():print(name,v['ReferencedWorkspaceFields'],'workspace references; missing:',v['MissingFields'])

if __name__=='__main__':main()

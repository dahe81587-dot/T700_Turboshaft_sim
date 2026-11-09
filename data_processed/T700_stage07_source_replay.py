"""Evaluate the generated adapter equations; this does not execute Simulink."""
import json
from pathlib import Path
import numpy as np
from T700_stage06d_build_simsetup import plain, numeric_table
from t700_thermo_compressor import ThermoTMATS
from t700_steady_adapter_check import evaluate_ss, solve_ss

ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'results'/'simsetup_t700'

def main():
    p=json.loads((ROOT/'data_processed'/'T700_adapter_numeric_parameters.json').read_text())
    construction=json.loads((OUT/'T700_simsetup_construction_checks.json').read_text())
    ref=construction['Reference']
    thermo=ThermoTMATS()
    seed=np.array(ref['XSeed'])
    source=dict(T2_R=518.67,P2_psia=14.696,P49_psia=ref['P49_psia'],
                Wf=476.3/3600,Qload=229.)
    bounds=dict(lower=[1,1,min(p['HPT']['PRVec']),min(p['FPT']['PRVec']),.65*44700,5000],
                upper=[15,3,max(p['HPT']['PRVec']),max(p['FPT']['PRVec']),44700,1.2*20900])
    trim=solve_ss(p,seed,source,thermo,max_iter=100,bounds=bounds)
    result=dict(SourceReplayOnly=True,SimulinkRun=False,
                ExperimentalCalibrationPerformed=False,ParameterFitPerformed=False,
                ReferenceBoundary=source,ReferenceSeedEvaluation=evaluate_ss(p,seed,source,thermo),
                ReferenceSolve=trim,LewisCases={})
    print('Ballin reference:',trim['Converged'],trim['ExitReason'],flush=True)
    script=ROOT/'data_processed'/'T700_experimental_data_preparation.m'
    inputs=numeric_table(script,'Input');measured=numeric_table(script,'Measured')
    # Each experimental case starts from the same source reference solution.
    # Experimental output values are used only for the post-solve comparison.
    x0=np.array(trim['X']) if trim['Converged'] else seed
    for row,target in zip(inputs,measured):
        case=int(row[0])
        bd=dict(P2_psia=row[1],T2_R=row[2],P49_psia=row[3],Qload=row[4],Wf=row[5]/3600)
        b=dict(lower=list(bounds['lower']),upper=list(bounds['upper']))
        b['lower'][4]=.65*44700*np.sqrt(row[2]/518.67)
        b['upper'][4]=44700*np.sqrt(row[2]/518.67)
        solved=solve_ss(p,x0,bd,thermo,max_iter=100,bounds=b)
        entry=dict(CaseID=case,Boundary=bd,Solve=solved,
                   DataRole='low_power_boundary' if case==1 else 'reserved_validation' if case in (3,5) else 'planned_calibration_not_fitted')
        if solved['Converged']:
            s=solved['Evaluation']['Stations'];x=solved['X']
            predicted=np.array([x[4],x[5],x[0],s['s3']['P'],s['s3']['T'],s['s45']['T'],s['s49']['T']])
            entry['Comparison']=dict(Fields=['Ng_rpm','Np_rpm','WA2_lb_s','P3_psia','T3_R','T45_R','T49_R'],
                Prediction=predicted,Experimental=target[1:],RelativeErrorPercent=100*(predicted-target[1:])/target[1:])
        result['LewisCases'][str(case)]=entry
        print('Lewis',case,solved['Converged'],solved['ExitReason'],flush=True)
    (OUT/'T700_source_replay_checks.json').write_text(json.dumps(plain(result),indent=2,allow_nan=False),encoding='utf-8')
    print('T700_SOURCE_REPLAY_COMPLETE')

if __name__=='__main__':main()

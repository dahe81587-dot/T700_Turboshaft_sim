% Repair a candidate copy first; leave the original untouched until verified.
root=fileparts(fileparts(mfilename('fullpath')));
modelDir=fullfile(root,'model');
resultDir=fullfile(root,'results','dyn_compile_20261109');
candidateDir=fullfile(resultDir,'candidate');
if ~isfolder(candidateDir), mkdir(candidateDir); end
addpath(modelDir);
diary(fullfile(resultDir,'repair_compile.txt'));
model='T700_Dyn';
load_system(fullfile(modelDir,[model '.mdl']));
save_system(model,fullfile(candidateDir,[model '.mdl']));
set_param(model,'PreLoadFcn','T700_Dyn_initialize;', ...
    'InitFcn','T700_Dyn_initialize;');
T700_Dyn_initialize('ballin_trim1');
try
    set_param(model,'SimulationCommand','update');
    fprintf('STAGE1_PASS\n');
catch err
    fprintf('STAGE1_FAIL\n%s\n',getReport(err,'extended','hyperlinks','off'));
end
inner=[model '/While Iterator' newline 'Subsystem'];
nr=[inner '/Iterative NR Solver w JacobianCalc'];
set_param(nr,'SJac_Per_M','MWS.Dynamic.J_Calc_Per', ...
    'SNR_Mx_M','MWS.Dynamic.Upper','SNR_Mn_M','MWS.Dynamic.Lower', ...
    'Cond_Limits_M','MWS.Dynamic.C_Lim');
set_param([inner '/Demux'],'Outputs','4');
set_param([inner '/Mux1'],'Inputs','4');
set_param(model,'SolverType','Fixed-step','Solver','ode4');
try
    set_param(model,'SimulationCommand','update');
    fprintf('STAGE2_PASS\n');
catch err
    fprintf('STAGE2_FAIL\n%s\n',getReport(err,'extended','hyperlinks','off'));
end
save_system(model);
diary off;

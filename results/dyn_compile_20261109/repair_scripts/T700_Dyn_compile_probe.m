% Reproduce the saved dynamic model update without changing the model.
probeRoot=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(probeRoot,'model'));
probeResult=fullfile(probeRoot,'results','dyn_compile_20261109');
if ~isfolder(probeResult), mkdir(probeResult); end
diary(fullfile(probeResult,'compile_before.txt'));
try
    load_system(fullfile(probeRoot,'model','T700_Dyn.mdl'));
    fprintf('MODEL_FILE: %s\n',get_param('T700_Dyn','FileName'));
    fprintf('SOLVER: %s\n',get_param('T700_Dyn','Solver'));
    set_param('T700_Dyn','SimulationCommand','update');
    fprintf('COMPILE_PASS\n');
catch probeError
    fprintf('COMPILE_FAIL\n%s\n',getReport(probeError,'extended','hyperlinks','off'));
end
diary off;

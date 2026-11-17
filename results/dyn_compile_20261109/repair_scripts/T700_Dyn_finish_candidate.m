root=fileparts(fileparts(mfilename('fullpath')));
modelDir=fullfile(root,'model');
resultDir=fullfile(root,'results','dyn_compile_20261109');
addpath(modelDir);
diary(fullfile(resultDir,'candidate_validation.txt'));
model='T700_Dyn';
load_system(fullfile(resultDir,'candidate',[model '.mdl']));
output=[model '/OutputStations'];
selector=[output '/Bus' newline 'Selector'];
ph=get_param(selector,'PortHandles');
for port=ph.Outport
    line=get_param(port,'Line');
    if line~=-1, delete_line(line); end
end
delete_block([output '/To Workspace']);
delete_block([output '/To Workspace6']);
set_param(selector,'OutputSignals', ...
    'StationData.S2,StationData.S3,StationData.S41,StationData.S45,StationData.S49,Data.CompData,Data.GGTData,Data.FPTData');
destinations={'To Workspace1','To Workspace2','To Workspace3','To Workspace4', ...
    'To Workspace5','To Workspace7','To Workspace8','To Workspace9'};
variables={'S2','S3','S41','S45','S49','CompData','GGTData','FPTData'};
for k=1:numel(destinations)
    set_param([output '/' destinations{k}],'VariableName',variables{k});
    add_line(output,['Bus' newline 'Selector/' num2str(k)], ...
        [destinations{k} '/1'],'autorouting','on');
end
% The original PI compares Nf demand against Ng; connect the Np feedback.
piPorts=get_param([model '/Simple PI controller'],'PortHandles');
delete_line(get_param(piPorts.Inport(2),'Line'));
add_line(model,'FPT_integrator/1','Simple PI controller/2','autorouting','on');
try
    set_param(model,'SimulationCommand','update');
    fprintf('CANDIDATE_COMPILE_PASS\n');
    save_system(model);
catch err
    fprintf('CANDIDATE_COMPILE_FAIL\n%s\n',getReport(err,'extended','hyperlinks','off'));
    save_system(model);
    diary off;
    rethrow(err);
end
try
    out=sim(model,'StopTime','0.15','ReturnWorkspaceOutputs','on');
    fprintf('CANDIDATE_SMOKE_PASS\n');
    disp(out.who);
    save(fullfile(resultDir,'candidate_smoke.mat'),'out','-v7.3');
catch err
    fprintf('CANDIDATE_SMOKE_FAIL\n%s\n',getReport(err,'extended','hyperlinks','off'));
end
diary off;

function MWS = Turboshaft_initialize
% Original example workspace. Uses model/SimSetup, not SimSetup_T700.
% Does not open/edit/run a model; the example load and dynamic trim are pending.
modelDir=fileparts(mfilename('fullpath'));
setupRoot=fullfile(modelDir,'SimSetup');
addpath(modelDir,'-begin'); addpath(setupRoot,'-begin');
MWS=struct('engName','Turboshaft_example','top_level',modelDir);
names={'setup_Solve_temp';'setup_Inputs';'setup_Boundary'; ...
    'setup_HPC';'setup_FPT';'setup_Shaft';'setup_Noz'; ...
    'setup_HPT';'setup_Burner';'setup_Duct';'setup_Inlet'};
files=cell(size(names));
for k=1:numel(names)
    files{k}=which(names{k});
    assert(strcmpi(files{k},fullfile(setupRoot,[names{k} '.m'])),'Wrong example setup: %s',names{k});
    MWS=feval(names{k},MWS);
end
MWS.Input.NRICDyn=nan(4,1);
MWS.Input.LP_Shaft=NaN;
MWS.Input.FARin=NaN;
MWS.Project.Root=fileparts(modelDir);
MWS.Project.SetupRoot=setupRoot;
MWS.Project.Engine='Turboshaft_example';
MWS.Project.DynamicTrimReady=false;
MWS.Project.SetupFiles=table(names,files,'VariableNames',{'Function','File'});
assignin('base','MWS',MWS);
fprintf('Original Turboshaft parameters loaded. Qload/dynamic trim remain user inputs.\n');
end

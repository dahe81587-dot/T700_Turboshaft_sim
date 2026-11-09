function MWS = T700_initialize
% Build the initialization framework.
% T700 physical parameters are not applied at this stage.

modelDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(modelDir);
setupDir = fullfile(modelDir, 'SimSetup');

addpath(modelDir, '-begin');
addpath(setupDir, '-begin');

previousDir = pwd;
restoreDir = onCleanup(@() cd(previousDir));
cd(modelDir);

setupNames = {
    'setup_Solve_temp'
    'setup_Inputs'
    'setup_Boundary'
    'setup_HPC'
    'setup_FPT'
    'setup_Shaft'
    'setup_Noz'
    'setup_HPT'
    'setup_Burner'
    'setup_Duct'
    'setup_Inlet'
};

MWS = struct;
MWS.engName = 'T700_validation';
MWS.top_level = modelDir;
setupFiles = cell(size(setupNames));

for k = 1:numel(setupNames)
    setupFiles{k} = which(setupNames{k});
    expectedFile = fullfile(setupDir, [setupNames{k} '.m']);

    assert(strcmpi(setupFiles{k}, expectedFile), ...
        'Parameter source mismatch: %s -> %s', ...
        setupNames{k}, setupFiles{k});

    MWS = feval(setupNames{k}, MWS);
end

dataFile = fullfile(projectDir, 'data_processed', ...
    'T700_Lewis_prepared.mat');

assert(isfile(dataFile), 'Missing data file: %s', dataFile);

referenceData = load(dataFile, 'T700');
MWS.Reference = referenceData.T700;

MWS.Project.Root = projectDir;
MWS.Project.T700ParametersApplied = false;
MWS.Project.DynamicTrimReady = false;

MWS.Project.SetupFiles = table(setupNames, setupFiles, ...
    'VariableNames', {'Function', 'File'});

% Pending dynamic values:
% obtain these from a converged steady-state solution later.
MWS.Input.NRICDyn = nan(4,1);
MWS.Input.LP_Shaft = NaN;
MWS.Input.FARin = NaN;

assignin('base', 'MWS', MWS);
end
function Plan = T700_stage04_data_plan
% Record data provenance and planned calibration/validation roles.

processedDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(processedDir);
resultDir = fullfile(projectDir, 'results');

diary(fullfile(resultDir, 'stage04_data_plan_check.txt'));
stopDiary = onCleanup(@() diary('off'));

S = load(fullfile(processedDir, ...
    'T700_Lewis_prepared.mat'), 'T700');

Plan = struct;

%% 1. Reference engine and experimental engine

Plan.PrimaryModel = 'Ballin public T700 reference model';
Plan.ExperimentalEngine = 'NASA Lewis experimental test article';

Plan.ParameterRule = ...
    'Keep public-reference and Lewis-adapted parameters distinguishable';

Plan.ExperimentalComparison = ...
    'Check engine compatibility before interpreting experimental errors';

%% 2. Source register
% Origin identifies shared underlying reference data.

Plan.Sources = cell2table({
    'Ballin1988', 'Appendix A', ...
    'Component functions', 'Build public reference', 'Ballin_reference'

    'Ballin1988', 'Figures 6-8', ...
    'Simulation results', 'Steady benchmark', 'Ballin_reference'

    'Ballin1988', 'Figures 9-10', ...
    'Simulation results', 'Transient benchmark', 'Ballin_reference'

    'Hart1984', 'Tables I-II', ...
    'Experimental data', 'Lewis comparison', 'NASA_Lewis_tests'

    'Ballin1988', 'Tables 2-3', ...
    'Reused experimental data', 'Cross-check', 'NASA_Lewis_tests'

    'Novikov2012', 'Chapter 4', ...
    'Simulation reproduction', 'Method reference', 'Ballin_reference'
}, 'VariableNames', {
    'Source', 'Location', 'DataType', 'Purpose', 'Origin'
});

%% 3. Planned roles for Lewis experimental cases
% These roles apply if Lewis-specific parameter adaptation is performed.

Plan.Lewis.CalibrationIDs = [2 4 6];
Plan.Lewis.HoldoutIDs = [3 5];
Plan.Lewis.EdgeIDs = 1;

CaseID = S.T700.Input.CaseID;
Role = strings(size(CaseID));

Role(ismember(CaseID, Plan.Lewis.CalibrationIDs)) = ...
    "CalibrationReserved";

Role(ismember(CaseID, Plan.Lewis.HoldoutIDs)) = ...
    "ValidationReserved";

Role(ismember(CaseID, Plan.Lewis.EdgeIDs)) = ...
    "LowPowerBoundary";

assert(all(strlength(Role) > 0), 'Some cases have no assigned role.');

assert(isempty(intersect(Plan.Lewis.CalibrationIDs, ...
    Plan.Lewis.HoldoutIDs)), 'Calibration and validation IDs overlap.');

Plan.Lewis.CaseRoles = table(CaseID, Role);

%% 4. Boundary and reference conventions

Plan.Lewis.Inputs = {'P2', 'T2', 'P49', 'Wf', 'Qload'};
Plan.Lewis.ComparisonOutputs = ...
    {'Ng', 'Np', 'WA2', 'P3', 'T3', 'T45', 'T49'};

Plan.CompressorDigitizationSource = ...
    'Ballin Figure A1: lbm/s and Ps3/P2';

Plan.NovikovAppendixDUnitsVerified = false;

% Ballin Figures 9-10 suppress Np integration.
Plan.TransientReference.DataType = 'Simulation-to-simulation';
Plan.TransientReference.FixedNp = true;
Plan.TransientReference.FuelSteps_lb_h = [400 775; 400 125];

%% 5. Linearization scope

Plan.Linearization.SinglePointRequired = true;
Plan.Linearization.MultiPointRequired = false;
Plan.Linearization.OperatingPoint = 'Select after steady convergence';
Plan.Linearization.ControlInput = 'Wf';
Plan.Linearization.LoadDisturbance = 'Qload';

%% 6. Save and display

save(fullfile(processedDir, 'T700_data_plan.mat'), 'Plan');

disp('--- Source register ---');
disp(Plan.Sources);

disp('--- Planned experimental case roles ---');
disp(Plan.Lewis.CaseRoles);

fprintf('\nCalibration reserved: %s\n', ...
    mat2str(Plan.Lewis.CalibrationIDs));

fprintf('Validation reserved: %s\n', ...
    mat2str(Plan.Lewis.HoldoutIDs));

fprintf('Boundary cases: %s\n', ...
    mat2str(Plan.Lewis.EdgeIDs));

fprintf('Single-point linearization required: %d\n', ...
    Plan.Linearization.SinglePointRequired);

fprintf('Multi-point linearization required: %d\n', ...
    Plan.Linearization.MultiPointRequired);

fprintf('\nSTAGE04_DATA_PLAN_READY\n');
end
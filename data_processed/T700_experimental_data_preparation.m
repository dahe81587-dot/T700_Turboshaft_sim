%% Stage 02: T700 experimental data preparation

tsProject = ...
    'E:\postgraduate\09_Turboshaft\06_simulink\example\T700_validation';

assert(isfolder(fullfile(tsProject, 'data_raw')), ...
    '没有找到 data_raw，请检查第 1 次操作的目录。');

assert(isfolder(fullfile(tsProject, 'data_processed')), ...
    '没有找到 data_processed，请检查工程目录。');

%% 1. Source information

T700raw = struct;

T700raw.Source.Report = 'NASA-TM-83579';
T700raw.Source.File = fullfile(tsProject, 'sources', ...
    'NASA-TM-83579_Hart_Wenzel_1984.pdf');

T700raw.Source.PDFPage = 35;
T700raw.Source.InputTable = 'I';
T700raw.Source.MeasuredTable = 'II, Experimental rows only';
T700raw.Source.Engine = 'NASA Lewis experimental test article';

%% 2. Table I: boundary conditions
% Columns:
% CaseID, P2 [psia], T2 [degR], P49 [psia],
% Qload [lbf*ft], Wf [lbm/hr]

T700raw.Input = array2table([
    1   14.37   516.7   14.37    30.1   140.1
    2   14.17   515.6   14.43    90.1   297.2
    3   14.16   508.3   14.46   148.3   372.0
    4   14.09   508.0   14.60   206.5   458.4
    5   14.02   507.2   14.63   274.3   560.6
    6   13.92   507.2   14.72   360.8   694.4
], 'VariableNames', {
    'CaseID', 'P2_psia', 'T2_R', 'P49_psia', ...
    'Qload_lbf_ft', 'Wf_lb_h'
});

%% 3. Table II: measured values
% Columns:
% CaseID, Ng [rpm], Np [rpm], WA2 [lbm/s],
% P3 [psia], T3 [degR], T45 [degR], T49 [degR]

T700raw.Measured = array2table([
    1   29480   10995   3.20    58.0    832   1413   1345
    2   37875   19995   5.16   113.1   1026   1577   1402
    3   39236   19995   6.16   139.0   1081   1626   1410
    4   40409   19995   6.92   161.1   1127   1731   1457
    5   41393   19995   7.66   184.8   1173   1838   1529
    6   42880   19995   8.50   211.9   1228   1974   1600
], 'VariableNames', {
    'CaseID', 'Ng_rpm', 'Np_rpm', 'WA2_lb_s', ...
    'P3_psia', 'T3_R', 'T45_R', 'T49_R'
});

assert(isequal(T700raw.Input.CaseID, ...
    T700raw.Measured.CaseID), '输入与实测值的工况编号不一致。');

save(fullfile(tsProject, 'data_raw', ...
    'T700_Lewis_raw.mat'), 'T700raw');

%% 4. Model-native units

T700 = struct;
T700.Source = T700raw.Source;

T700.Input = removevars(T700raw.Input, 'Wf_lb_h');
T700.Input.Wf_lb_s = T700raw.Input.Wf_lb_h / 3600;

T700.Reference = T700raw.Measured;

%% 5. SI boundary conditions

psiToPa = 6894.757293168;
lbToKg = 0.45359237;
lbfFtToNm = 1.3558179483314;

R = T700raw.Input;

T700.SI_Input = table( ...
    R.CaseID, ...
    R.P2_psia * psiToPa, ...
    R.T2_R * 5/9, ...
    R.P49_psia * psiToPa, ...
    R.Qload_lbf_ft * lbfFtToNm, ...
    R.Wf_lb_h / 3600 * lbToKg, ...
    'VariableNames', {
    'CaseID', 'P2_Pa', 'T2_K', 'P49_Pa', ...
    'Qload_Nm', 'Wf_kg_s'
});

%% 6. Derived shaft power
% Calculated from measured torque and speed.
% This is not an independently measured power channel.

Pshaft_kW = T700.SI_Input.Qload_Nm .* ...
    T700.Reference.Np_rpm * (2*pi/60) / 1000;

T700.Derived = table(R.CaseID, Pshaft_kW, ...
    'VariableNames', {'CaseID', 'Pshaft_kW'});

save(fullfile(tsProject, 'data_processed', ...
    'T700_Lewis_prepared.mat'), 'T700');

%% 7. Display checks

disp('--- Model input data ---');
disp(T700.Input);

disp('--- Measured reference data ---');
disp(T700.Reference);

disp('--- Case 4: SI boundary conditions ---');
disp(T700.SI_Input(4,:));

disp('--- Derived shaft power ---');
disp(T700.Derived);

fprintf('\nSTAGE02_DATA_READY\n');
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'model'));
T700_initialize('ballin_trim1');
data=load(fullfile(root,'model','SteadyState','results','T700_SS_result_check.mat'));
disp(fieldnames(data));
for key=fieldnames(data)'
    value=data.(key{1});
    fprintf('VARIABLE %s\n',key{1});
    if isstruct(value), disp(fieldnames(value)); end
end
if isfield(data,'report')
    disp(data.report.X);
    disp(data.report.Boundary);
    disp(data.report.Stations.S3);
    disp(data.report.CheckedAt);
end
if isfield(data,'Results'), disp(fieldnames(data.Results)); end
load_system(fullfile(root,'model','T700_Dyn.mdl'));
disp(get_param('T700_Dyn/GGT_integrator','ReferenceBlock'));
disp(get_param('T700_Dyn/GGT_integrator','DialogParameters'));

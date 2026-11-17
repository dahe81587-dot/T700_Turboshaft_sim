function report=T700_Dyn_check(modelFile,stopTime)
% Compile and run a finite-value smoke check; no experimental validation.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'model'));
if nargin<1, modelFile=fullfile(root,'model','T700_Dyn.mdl'); end
load_system(modelFile);
assert(strcmpi(get_param('T700_Dyn','FileName'),modelFile), ...
    'T700:Dyn:WrongModel','已加载的 T700_Dyn 并非待检查文件。');
set_param('T700_Dyn','SimulationCommand','update');
MWS=evalin('base','MWS');
if nargin<2, stopTime=MWS.in.SimTime; end
out=sim('T700_Dyn','StopTime',num2str(stopTime,17),'ReturnWorkspaceOutputs','on');
required={'S2','S3','S41','S45','S49','CompData','GGTData','FPTData', ...
    'FAR','Nf_dmd','P49_calc','P49_target','P49_error','Plant_Data'};
available=out.who;
assert(all(ismember(required,available)),'T700:Dyn:MissingLogs','动态日志不完整。');
count=0;
for k=1:numel(required)
    count=count+checkFinite(out.get(required{k}),required{k},stopTime);
end
ng=out.CompData.Nmech;
np=out.FPTData.Nmech;
report=struct('CheckedAt',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'ModelFile',modelFile,'Profile',MWS.Boundary.Profile, ...
    'CompilationPassed',true,'SimulationPassed',true,'StopTime_s',stopTime, ...
    'FiniteTimeseriesChecked',count, ...
    'NgInitial_rpm',double(ng.Data(1)),'NgFinal_rpm',double(ng.Data(end)), ...
    'NpInitial_rpm',double(np.Data(1)),'NpFinal_rpm',double(np.Data(end)), ...
    'ExperimentalValidationPerformed',false,'TransientValidationPerformed',false);
disp(report);
end

function count=checkFinite(value,label,stopTime)
count=0;
if isa(value,'timeseries')
    assert(~isempty(value.Data) && all(isfinite(value.Data(:))), ...
        'T700:Dyn:Nonfinite','日志 %s 包含非有限值或为空。',label);
    assert(abs(value.Time(end)-stopTime)<1e-9,'T700:Dyn:Incomplete', ...
        '日志 %s 未到达指定结束时刻。',label);
    count=1;
elseif isstruct(value)
    names=fieldnames(value);
    for k=1:numel(names)
        count=count+checkFinite(value.(names{k}),[label '.' names{k}],stopTime);
    end
else
    error('T700:Dyn:UnexpectedLog','无法识别日志 %s 的类型：%s。',label,class(value));
end
end

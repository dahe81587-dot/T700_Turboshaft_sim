function [figures,R] = PlotData(mode,source,MWS)
% One plot entry for both T700 and the original Turboshaft example.
% PlotData('ss')                  -> station profile + maps + available speeds
% PlotData('dyn',Plant_Data)      -> time histories + maps + available speeds
% PlotData('ss',out) / PlotData('dyn',out) also accept SimulationOutput/struct.
% PlotData('maps')                -> parameter maps before simulation
% Optional third input supplies MWS explicitly; default is base-workspace MWS.
% Reads existing values only. Does not initialize, open/edit/run/close a model.
if nargin<1 || isempty(mode), mode='ss'; end
mode=lower(char(string(mode)));
assert(ismember(mode,{'ss','dyn','maps'}),'绘图模式必须为 ss、dyn 或 maps。');
if nargin<3
    assert(evalin('base','exist(''MWS'',''var'')')==1,'请先运行目标发动机的初始化函数。');
    MWS=evalin('base','MWS');
end
if strcmp(mode,'maps')
    R=struct('Mode','maps','Components',struct,'ConvergenceChecked',false);
    figures=drawMaps(MWS,R);
    return
end
if nargin<2 || isempty(source)
    [stationFigure,R]=readAndPlotStations(mode);
else
    [stationFigure,R]=readAndPlotStations(mode,source);
end
figures=[stationFigure;drawMaps(MWS,R)];
speedFigure=drawSpeeds(R);
if ~isempty(speedFigure), figures(end+1,1)=speedFigure; end
end

function fig=drawMaps(MWS,R)
% Legacy example namespaces are adapted locally; the supplied MWS is unchanged.
if isfield(MWS,'Compressor'), compressor=MWS.Compressor; else, compressor=MWS.('HPC'); end
if isfield(MWS,'GGT'), ggt=MWS.GGT; else, ggt=MWS.('HPT'); end
fpt=MWS.FPT;
fig=figure('Name','Engine component maps'); tiledlayout(2,2);
nexttile; hold on;
for k=1:numel(compressor.NcVec)
    plot(compressor.WcArray(k,:),compressor.PRArray(k,:), ...
        'DisplayName',sprintf('NcMap = %.4g',compressor.NcVec(k)));
end
markPoint(R,'Compressor','WcMap','PRMap');
xlabel('Map corrected flow [lbm/s]'); ylabel('Map pressure ratio');
title('Compressor flow/pressure map'); grid on; legend('Location','eastoutside');
nexttile; plot(compressor.WcArray',compressor.EffArray'); grid on;
xlabel('Map corrected flow [lbm/s]'); ylabel('Map efficiency'); title('Compressor efficiency');
components={ggt,fpt}; names={'GGT','FPT'};
for k=1:2
    C=components{k}; nexttile;
    if isequal(C.WcArray,repmat(C.WcArray(1,:),size(C.WcArray,1),1)) && ...
            isequal(C.EffArray,repmat(C.EffArray(1,:),size(C.EffArray,1),1))
        flow=C.WcArray(1,:); efficiency=C.EffArray(1,:);
    else
        flow=C.WcArray'; efficiency=C.EffArray';
    end
    yyaxis left; plot(C.PRVec,flow); hold on;
    markPoint(R,names{k},'PRMap','WcMap'); ylabel('Map corrected flow [lbm/s]');
    yyaxis right; plot(C.PRVec,efficiency); ylabel('Map efficiency');
    xlabel('Map pressure ratio'); title([names{k} ' flow/efficiency map']); grid on;
end
end

function markPoint(R,component,xfield,yfield)
if ~isfield(R.Components,component), return; end
data=unwrap(R.Components.(component));
xvalue=getValue(data,xfield); yvalue=getValue(data,yfield);
if isempty(xvalue) || isempty(yvalue), return; end
[~,x]=series(xvalue); [~,y]=series(yvalue);
assert(numel(x)==numel(y),'部件 %s 的特性图诊断数据长度不一致。',component);
if strcmp(R.Mode,'ss')
    plot(x(end),y(end),'ko','MarkerFaceColor','k','DisplayName','Final solver sample');
else
    plot(x,y,'k-','LineWidth',1.5,'DisplayName','Logged trajectory');
    plot(x(end),y(end),'ko','MarkerFaceColor','k','HandleVisibility','off');
end
end

function fig=drawSpeeds(R)
components={'Compressor','GGT','FPT'}; records=cell(3,1); count=0;
for k=1:3
    if isfield(R.Components,components{k})
        data=unwrap(R.Components.(components{k}));
        value=getValue(data,'Nmech');
        if ~isempty(value)
            [t,y,timeKnown]=series(value); count=count+1;
            records{count}=struct('Name',components{k},'Time',t,'Data',y,'TimeKnown',timeKnown);
        end
    end
end
fig=[];
if count==0, return; end
fig=figure('Name','Logged component shaft speeds');
if strcmp(R.Mode,'ss')
    labels=cell(count,1); values=zeros(count,1);
    for k=1:count
        labels{k}=records{k}.Name; values(k)=records{k}.Data(end);
    end
    bar(values); xticks(1:count); xticklabels(labels); xlabel('Final solver sample');
else
    hold on; allTimed=true;
    for k=1:count
        plot(records{k}.Time,records{k}.Data,'DisplayName',records{k}.Name);
        allTimed=allTimed && records{k}.TimeKnown;
    end
    if allTimed, xlabel('Time [s]'); else, xlabel('Sample index / supplied time'); end
    legend('Location','best');
end
ylabel('Mechanical speed [rpm]'); grid on;
end

function [fig,R] = readAndPlotStations(mode,source)
% Station plots for both projects, without changing models or workspace data.
% SS uses lowercase station logs in the base workspace.
% Dyn accepts its nested Plant_Data bus or uppercase individual logs.
% SimulationOutput/struct inputs remain supported.
% A steady plot uses final NR samples; it does not assert steady convergence.
mode=lower(char(string(mode)));
assert(ismember(mode,{'ss','dyn'}),'结果绘图模式必须为 ss 或 dyn。');
if nargin<2
    source=struct;
    if strcmp(mode,'ss')
        names={'s2','s3','s4','s5','s6','C_Data','GGT_Data','FPT_Data'};
    else
        names={'Plant_Data','S2','S3','S4','S5','S6','CompData','GGTData','FPTData'};
    end
    for k=1:numel(names)
        if evalin('base',sprintf('exist(''%s'',''var'')',names{k}))==1
            source.(names{k})=evalin('base',names{k});
        end
    end
end
if strcmp(mode,'ss')
    stationKeys={'s2','s3','s4','s5','s6'};
    componentKeys={'C_Data','GGT_Data','FPT_Data'};
    stationSource=source; componentSource=source;
    origin='SS individual logs';
else
    plant=getValue(source,'Plant_Data');
    if isempty(plant) && isstruct(source) && isfield(source,'StationData'), plant=source; end
    plant=unwrap(plant);
    if isstruct(plant) && isfield(plant,'StationData')
        stationSource=unwrap(plant.StationData);
        componentSource=getValue(plant,'Data');
        origin='Plant_Data.StationData';
    else
        stationSource=source; componentSource=source;
        origin='Dyn individual uppercase logs';
    end
    stationKeys={'S2','S3','S4','S5','S6'};
    componentKeys={'CompData','GGTData','FPTData'};
end
canonical={'S2','S3','S41','S45','S49'};
locations={'Compressor inlet','Compressor outlet','GGT inlet','FPT inlet','FPT outlet'};
fields={'W','Tt','Pt','FAR'};
units={'lbm/s','degR','psia','-'};
R=struct('Mode',mode,'Source',origin,'ConvergenceChecked',false,'Stations',struct,'Components',struct);
last=nan(5,4);
for k=1:5
    station=unwrap(getValue(stationSource,stationKeys{k}));
    assert(isstruct(station) && isscalar(station), ...
        '缺少气路站位日志 %s，请明确提供目标工况的仿真结果。',stationKeys{k});
    for j=1:4
        signal=getValue(station,fields{j});
        assert(~isempty(signal),'站位 %s 缺少物理量 %s。',stationKeys{k},fields{j});
        [t,y,timeKnown]=series(signal);
        R.Stations.(canonical{k}).(fields{j})=struct('Time',t,'Data',y,'TimeKnown',timeKnown);
        last(k,j)=y(end);
    end
end
components={'Compressor','GGT','FPT'};
for k=1:3
    value=getValue(componentSource,componentKeys{k});
    if ~isempty(value), R.Components.(components{k})=value; end
end
R.Mapping=table(canonical(:),stationKeys(:),locations(:), ...
    'VariableNames',{'CanonicalStation','LoggedStation','Location'});
R.LastValues=array2table(last,'VariableNames',fields,'RowNames',canonical);
fig=figure('Name',['Engine results: ' mode]); tiledlayout(2,2);
for j=1:4
    nexttile;
    if strcmp(mode,'ss')
        bar(last(:,j)); xticks(1:5); xticklabels(canonical);
        xlabel('Physical station; final solver sample');
    else
        hold on; allTimed=true;
        for k=1:5
            v=R.Stations.(canonical{k}).(fields{j});
            plot(v.Time,v.Data,'DisplayName',canonical{k});
            allTimed=allTimed && v.TimeKnown;
        end
        if allTimed, xlabel('Time [s]'); else, xlabel('Sample index / supplied time'); end
        legend('Location','best');
    end
    ylabel([fields{j} ' [' units{j} ']']); grid on;
end
displayMapping=R.Mapping;
displayMapping.Properties.VariableNames={'物理站位','日志站位','日志位置'};
fprintf('站位映射：\n'); disp(displayMapping);
fprintf('各站位最终值（列为物理量符号，单位见图）：\n'); disp(R.LastValues);
end

function value=getValue(source,name)
value=[];
if isa(source,'Simulink.SimulationOutput')
    if any(strcmp(source.who,name)), value=source.get(name); end
elseif isstruct(source) && isscalar(source) && isfield(source,name)
    value=source.(name);
end
end

function value=unwrap(value)
if isa(value,'Simulink.SimulationData.Signal'), value=value.Values; end
if isa(value,'timeseries') && isstruct(value.Data) && isscalar(value.Data)
    value=value.Data;
end
end

function [t,y,timeKnown]=series(value)
value=unwrap(value); timeKnown=true;
if isa(value,'timeseries')
    t=value.Time; y=value.Data;
elseif isstruct(value) && isfield(value,'Time') && isfield(value,'Data')
    t=value.Time; y=value.Data;
elseif isstruct(value) && isfield(value,'time') && isfield(value,'signals')
    t=value.time; y=value.signals.values;
elseif isnumeric(value)
    y=value; t=(0:numel(y)-1)'; timeKnown=false;
else
    error('暂不支持此站位信号类型：%s。',class(value));
end
y=squeeze(y);
assert(isnumeric(y) && isvector(y) && ~isempty(y),'每个时间样本应对应一个标量信号。');
y=double(y(:)); t=double(t(:));
assert(numel(t)==numel(y),'信号的时间与数据长度不一致。');
end

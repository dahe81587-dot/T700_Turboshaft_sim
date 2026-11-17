function [figures,bundle] = T700_PlotComponentMaps(mode)
% Double-click entry for T700_Dyn/Plot Outputs.
% Uses TMATS.PlotCMap/PlotTMap in unscaled map coordinates and logged map data.
% 'cached' plots the compact archive without reading any live simulation data.
if nargin<1, mode='refresh'; end
if strcmpi(mode,'cached'), bundle=T700_MapHistory('read');
else, bundle=T700_MapHistory('refresh'); end
assert(all(isfield(bundle.Maps,{'Compressor','GGT','FPT'})), ...
    'T700:Maps:NoMaps','No matching component-map parameters are available.');
assert(~isempty(bundle.Runs),'T700:Maps:NoRuns', ...
    'No completed T700_Dyn component logs found. Run the model, then double-click Plot Outputs.');
assert(~isempty(which('TMATS.PlotCMap')) && ~isempty(which('TMATS.PlotTMap')), ...
    'T700:Maps:TMATSPath','T-MATS plotting functions are not on the MATLAB path.');
figures=gobjects(3,1);
names={'Compressor','GGT','FPT'};
titles={'压气机','燃气发生器涡轮 GGT','动力涡轮 FPT'};
for c=1:3
    tag=['T700_ComponentMap_' names{c}];
    fig=findall(groot,'Type','figure','Tag',tag);
    if isempty(fig)
        fig=figure('Tag',tag,'Color','w','NumberTitle','off', ...
            'Position',[90+40*c 100+30*c 1360 720]);
    else
        fig=fig(1); clf(fig);
    end
    set(fig,'Name',['T700 ' titles{c} '：特性图与运行轨迹']);
    state=struct('Component',names{c},'Title',titles{c}, ...
        'Map',bundle.Maps.(names{c}),'Runs',bundle.Runs, ...
        'Selected',1:numel(bundle.Runs),'Colors',lines(numel(bundle.Runs)));
    setappdata(fig,'T700MapState',state);
    render(fig);
    if strcmp(fig.Visible,'on'), figure(fig); end
    figures(c)=fig;
end
end

function render(fig)
state=getappdata(fig,'T700MapState');
delete(findall(fig,'Type','axes')); delete(findall(fig,'Type','legend'));
delete(findall(fig,'Type','uicontrol'));
ax1=axes(fig,'Position',[0.065 0.17 0.405 0.69]);
axes(ax1);
C=state.Map;
if strcmp(state.Component,'Compressor')
    TMATS.PlotCMap(C.NcVec,C.WcArray,C.PRArray,C.EffArray, ...
        'defsurge',C.WcMapSurge,C.PRMapSurge,'linesize',0.35,'efflines',7);
else
    % These T700 turbine adapters have identical rows across Nc. The native
    % efficiency contour is singular in Wc/PR space, so show eta separately.
    if max(C.WcArray(:))-min(C.WcArray(:))<=eps(max(abs(C.WcArray(:))))
        % Native PlotTMap sets identical x limits for a constant-flow table.
        % Draw its actual (vertical) curve with a finite display margin.
        plot(ax1,C.WcArray(1,:),C.PRVec,'k-','LineWidth',0.8);
        grid(ax1,'on'); box(ax1,'on');
        margin=max(0.02*abs(C.WcArray(1)),0.01);
        xlim(ax1,C.WcArray(1)+[-margin margin]);
    else
        TMATS.PlotTMap(C.NcVec,C.PRVec,C.WcArray,C.EffArray,'EffR','linesize',0.5);
    end
end
title(ax1,[state.Title '：流量—压比特性']);
xlabel(ax1,'Map 折合流量 WcMap [lbm/s]'); ylabel(ax1,'Map 压比 PRMap');
ax2=axes(fig,'Position',[0.555 0.17 0.405 0.69]); hold(ax2,'on');
if strcmp(state.Component,'Compressor')
    plot(ax2,C.WcArray',C.EffArray','Color',[0.7 0.7 0.7],'LineWidth',0.6);
    xlabel(ax2,'Map 折合流量 WcMap [lbm/s]');
else
    % Merge overlapping speed curves instead of suggesting distinct data.
    [~,uniqueRows]=unique([C.WcArray C.EffArray],'rows','stable');
    for k=uniqueRows(:)'
        plot(ax2,C.PRVec,C.EffArray(k,:),'Color',[0.65 0.65 0.65],'LineWidth',1);
    end
    xlabel(ax2,'Map 压比 PRMap');
end
ylabel(ax2,'Map 效率 EffMap'); title(ax2,[state.Title '：效率特性']);
grid(ax2,'on'); box(ax2,'on');
for ax=[ax1 ax2]
    set(findall(ax,'Type','line'),'HandleVisibility','off');
    set(findall(ax,'Type','contour'),'HandleVisibility','off');
    hold(ax,'on');
end
handles=gobjects(0); captions={};
for index=state.Selected
    r=state.Runs(index); d=r.Components.(state.Component);
    color=state.Colors(index,:); style=runStyle(r.Name);
    h=trajectory(ax1,d.Time,d.WcMap,d.PRMap,color,style,r.Name);
    handles(end+1)=h; captions{end+1}=r.Name; %#ok<AGROW>
    if strcmp(state.Component,'Compressor'), x=d.WcMap; else, x=d.PRMap; end
    trajectory(ax2,d.Time,x,d.EffMap,color,style,r.Name);
end
if ~isempty(handles)
    lg=legend(ax1,handles,captions,'Interpreter','none','FontSize',8, ...
        'Location','northwest');
    lg.ItemHitFcn=@toggleRun;
end
drawnow;
state.Axes=[ax1 ax2]; state.FullLimits=[xlim(ax1) ylim(ax1);xlim(ax2) ylim(ax2)];
setappdata(fig,'T700MapState',state);
uicontrol(fig,'Style','pushbutton','String','选择运行结果', ...
    'Units','normalized','Position',[0.065 0.92 0.12 0.045], ...
    'Callback',@(~,~)selectRuns(fig));
uicontrol(fig,'Style','pushbutton','String','放大轨迹范围', ...
    'Units','normalized','Position',[0.20 0.92 0.12 0.045], ...
    'Callback',@(~,~)zoomTrajectories(fig));
uicontrol(fig,'Style','pushbutton','String','恢复全图', ...
    'Units','normalized','Position',[0.335 0.92 0.10 0.045], ...
    'Callback',@(~,~)restoreLimits(fig));
note='彩色线：运行轨迹；空心圆：起点；实心方块：终点。点击图例可隐藏/显示一组轨迹。';
if ~strcmp(state.Component,'Compressor')
    note=[note newline '当前涡轮 Map 不随 Nc 行变化，转速线重合；右图单独显示效率。'];
end
uicontrol(fig,'Style','text','String',note,'HorizontalAlignment','left', ...
    'BackgroundColor','w','Units','normalized','Position',[0.065 0.035 0.88 0.075]);
end

function lineHandle=trajectory(ax,t,x,y,color,style,name)
lineHandle=plot(ax,x,y,'Color',color,'LineStyle',style,'LineWidth',1.8, ...
    'DisplayName',name,'Tag','T700MapTrajectory');
first=plot(ax,x(1),y(1),'o','Color',color,'MarkerFaceColor','w', ...
    'MarkerSize',7,'LineWidth',1.2,'HandleVisibility','off');
last=plot(ax,x(end),y(end),'s','Color',color,'MarkerFaceColor',color, ...
    'MarkerSize',6,'HandleVisibility','off');
lineHandle.UserData=[first last];
lineHandle.DataTipTemplate.DataTipRows(end+1)=dataTipTextRow('Time [s]',t);
end

function style=runStyle(name)
if contains(lower(name),'undisturbed')
    style=':';
elseif contains(name,'-1%') || contains(lower(name),'minus')
    style='--';
else
    style='-';
end
end

function toggleRun(~,event)
h=event.Peer;
if strcmp(h.Visible,'on'), visible='off'; else, visible='on'; end
fig=ancestor(h,'figure');
matching=findall(fig,'Type','line','Tag','T700MapTrajectory','DisplayName',h.DisplayName);
for lineHandle=matching(:)'
    set(lineHandle,'Visible',visible); set(lineHandle.UserData,'Visible',visible);
end
end

function selectRuns(fig)
state=getappdata(fig,'T700MapState');
[selection,ok]=listdlg('ListString',{state.Runs.Name},'SelectionMode','multiple', ...
    'InitialValue',state.Selected,'ListSize',[570 250], ...
    'PromptString','选择叠加的运行结果（可多选）','Name','T700 部件轨迹');
if ok && ~isempty(selection)
    state.Selected=selection; setappdata(fig,'T700MapState',state); render(fig);
end
end

function zoomTrajectories(fig)
state=getappdata(fig,'T700MapState');
for a=1:2
    handles=findall(state.Axes(a),'Type','line','Tag','T700MapTrajectory','Visible','on');
    if isempty(handles), continue; end
    x=[]; y=[];
    for h=handles(:)', x=[x;h.XData(:)]; y=[y;h.YData(:)]; end %#ok<AGROW>
    full=state.FullLimits(a,:);
    dx=max(0.15*(max(x)-min(x)),0.003*diff(full(1:2)));
    dy=max(0.15*(max(y)-min(y)),0.003*diff(full(3:4)));
    xlim(state.Axes(a),[min(x)-dx max(x)+dx]);
    ylim(state.Axes(a),[min(y)-dy max(y)+dy]);
end
end

function restoreLimits(fig)
state=getappdata(fig,'T700MapState');
for a=1:2
    xlim(state.Axes(a),state.FullLimits(a,1:2)); ylim(state.Axes(a),state.FullLimits(a,3:4));
end
end

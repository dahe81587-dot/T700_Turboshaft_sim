root='E:/postgraduate/09_Turboshaft/06_simulink/example/T700_validation';
addpath(fullfile(root,'model'));
S=load(fullfile(root,'results','component_maps_20261117','inspection.mat'),'MWS');
MWS=S.MWS; assignin('base','MWS',MWS);
set(groot,'DefaultFigureVisible','off');
load_system(fullfile(root,'model','T700_Dyn.mdl'));
cleanupModel=onCleanup(@()close_system('T700_Dyn',0));
button='T700_Dyn/While Iterator Subsystem/Subsystem';
original=get_param(button,'OpenFcn');
set_param(button,'OpenFcn','run(''PlotSSData.m'')');
open_system(button);
fig=findall(groot,'Type','figure','Tag','T700_ComponentMap_Compressor');
assert(numel(fig)==1,'Already-open model compatibility callback failed.');
figures=findall(groot,'Type','figure');
for fig=figures(:)'
 if ~startsWith(fig.Tag,'T700_ComponentMap_'), continue; end
 state=getappdata(fig,'T700MapState');
 lg=findall(fig,'Type','legend');
 h=findall(state.Axes(1),'Type','line','Tag','T700MapTrajectory');
 for j=1:numel(h)
  if ~contains(h(j).DisplayName,'_Wf'), feval(lg.ItemHitFcn,lg,struct('Peer',h(j))); end
 end
 visible=findall(fig,'Type','line','Tag','T700MapTrajectory','Visible','on');
 assert(numel(visible)==4,'Legend must toggle the same run on both plots.');
 buttonZoom=findall(fig,'Type','uicontrol','String','放大轨迹范围');
 feval(buttonZoom.Callback,[],[]);
 exportgraphics(fig,fullfile(root,'results','component_maps_20261117',[state.Component '_Wf_pair.png']),'Resolution',110);
end
set_param(button,'OpenFcn',original);
set_param('T700_Dyn','SimulationCommand','update');
reportFile=fullfile(root,'results','component_maps_20261117','verification.mat');
load(reportFile,'report'); report.AlreadyOpenModelCompatibilityPassed=true;
report.LegendTogglesBothAxesPassed=true;
save(reportFile,'report');
fid=fopen(fullfile(root,'results','component_maps_20261117','verification.json'),'w');
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true)); fclose(fid);
for f={'T700_MapHistory','T700_PlotComponentMaps','PlotSSData'}
 issues=checkcode(fullfile(root,'model',[f{1} '.m']),'-id');
 assert(isempty(issues),'Unexpected code-analysis diagnostics.');
end
close_system('T700_Dyn',0); close all;
fprintf('LIVE_BUTTON_COMPATIBILITY_AND_LEGEND_CHECK_COMPLETE\n');

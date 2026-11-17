root='E:/postgraduate/09_Turboshaft/06_simulink/example/T700_validation';
addpath(fullfile(root,'model'));
S=load(fullfile(root,'results','component_maps_20261117','inspection.mat'),'MWS');
MWS=S.MWS; assignin('base','MWS',MWS);
set(groot,'DefaultFigureVisible','off');
files={'T700_MapHistory.m','T700_PlotComponentMaps.m'};
for k=1:numel(files)
 issues=checkcode(fullfile(root,'model',files{k}),'-id');
 disp(issues);
end
Simulink.sdi.load(fullfile(root,'model','result','T700_Dyn.mldatx'));
bundle=T700_MapHistory('refresh');
fprintf('ARCHIVED_RUNS=%d\n',numel(bundle.Runs));
assert(numel(bundle.Runs)>=7,'Expected the saved trim and perturbation runs.');
bundle2=T700_MapHistory('refresh');
assert(numel(bundle2.Runs)==numel(bundle.Runs),'Repeated collection duplicated runs.');
for k=1:numel(bundle.Runs)
 fprintf('ARCHIVED %s\n',bundle.Runs(k).Name);
 for name={'Compressor','GGT','FPT'}
  d=bundle.Runs(k).Components.(name{1});
  assert(d.Time(end)>=59.99 && numel(d.Time)>1000);
  assert(all(isfinite([d.WcMap d.PRMap d.EffMap d.NcMap]),'all'));
 end
end
[figures,b]=T700_PlotComponentMaps('cached');
assert(numel(figures)==3);
components={'Compressor','GGT','FPT'};
for c=1:3
 state=getappdata(figures(c),'T700MapState');
 h=findall(state.Axes(1),'Type','line','Tag','T700MapTrajectory');
 assert(numel(h)==numel(bundle.Runs));
 for j=1:numel(h)
  idx=find(strcmp({bundle.Runs.Name},h(j).DisplayName),1);
  d=bundle.Runs(idx).Components.(components{c});
  assert(isequal(h(j).XData(:),d.WcMap) && isequal(h(j).YData(:),d.PRMap));
 end
 exportgraphics(figures(c),fullfile(root,'results','component_maps_20261117',[components{c} '.png']),'Resolution',110);
 buttons=findall(figures(c),'Type','uicontrol','String','放大轨迹范围');
 feval(buttons.Callback,[],[]);
 exportgraphics(figures(c),fullfile(root,'results','component_maps_20261117',[components{c} '_zoom.png']),'Resolution',110);
end
modelFile=fullfile(root,'model','T700_Dyn.mdl');
load_system(modelFile);
buttons=find_system('T700_Dyn','LookUnderMasks','all','FollowLinks','off','OpenFcn','T700_PlotComponentMaps;');
assert(numel(buttons)==1,'Plot button callback missing or ambiguous.');
fprintf('PLOT_BUTTON=%s\n',buttons{1});
eval(get_param(buttons{1},'OpenFcn'));
set_param('T700_Dyn','SimulationCommand','update');
fprintf('MODEL_UPDATE_PASSED\n');
report=struct('RunCount',numel(bundle.Runs),'RunNames',{{bundle.Runs.Name}}, ...
 'CoordinateChecksPassed',true,'RepeatedCollectionNoDuplicates',true, ...
 'ButtonCallbackPassed',true,'ModelUpdatePassed',true,'SimulationPerformed',false);
save(fullfile(root,'results','component_maps_20261117','verification.mat'),'report');
fid=fopen(fullfile(root,'results','component_maps_20261117','verification.json'),'w');
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true)); fclose(fid);
close_system('T700_Dyn',0); close all;
fprintf('COMPONENT_MAP_VERIFICATION_COMPLETE\n');

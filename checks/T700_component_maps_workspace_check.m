root='E:/postgraduate/09_Turboshaft/06_simulink/example/T700_validation';
addpath(fullfile(root,'model'));
S=load(fullfile(root,'results','component_maps_20261117','inspection.mat'),'MWS');
MWS=S.MWS; assignin('base','MWS',MWS);
bundle=T700_MapHistory('read');
keys={'CompData','GGTData','FPTData'}; names={'Compressor','GGT','FPT'};
source=struct;
for k=1:3
 d=bundle.Runs(1).Components.(names{k});
 component=struct;
 for f={'WcMap','PRMap','EffMap','NcMap'}
  component.(f{1})=timeseries(d.(f{1}),d.Time);
 end
 source.(keys{k})=component;
 assignin('base',keys{k},component);
end
assert(isempty(Simulink.sdi.getAllRunIDs));
refreshed=T700_MapHistory('refresh');
assert(numel(refreshed.Runs)==numel(bundle.Runs),'Workspace fallback duplicated a cached trajectory.');
refreshed=T700_MapHistory('add',source,bundle.Runs(1).Name);
assert(numel(refreshed.Runs)==numel(bundle.Runs));
set(groot,'DefaultFigureVisible','off');
figures=T700_PlotComponentMaps;
assert(numel(figures)==3,'Plotting requires a live Inspector run.');
reportFile=fullfile(root,'results','component_maps_20261117','verification.mat');
load(reportFile,'report');
report.WorkspaceLoggingWithoutSDIPassed=true;
report.CachedPlottingWithoutSDIPassed=true;
save(reportFile,'report');
fid=fopen(fullfile(root,'results','component_maps_20261117','verification.json'),'w');
fprintf(fid,'%s',jsonencode(report,'PrettyPrint',true)); fclose(fid);
issues=struct;
for f={'T700_MapHistory','T700_PlotComponentMaps'}
 issues.(f{1})=checkcode(fullfile(root,'model',[f{1} '.m']),'-id');
end
fid=fopen(fullfile(root,'results','component_maps_20261117','code_analysis.json'),'w');
fprintf(fid,'%s',jsonencode(issues,'PrettyPrint',true)); fclose(fid);
close all;
fprintf('WORKSPACE_AND_CACHE_VERIFICATION_COMPLETE\n');

root='E:/postgraduate/09_Turboshaft/06_simulink/example/T700_validation';
addpath(fullfile(root,'model'));
MWS=T700_Dyn_initialize('ballin_trim1');
fprintf('TMATS_CMAP=%s\n',which('TMATS.plotCMap'));
fprintf('TMATS_TMAP=%s\n',which('TMATS.plotTMap'));
fprintf('TURBINE_MAP_SIZE GGT=%s FPT=%s\n',mat2str(size(MWS.GGT.WcArray)),mat2str(size(MWS.FPT.WcArray)));
fprintf('LOADING_SAVED_SESSION\n');
Simulink.sdi.load(fullfile(root,'model','result','T700_Dyn.mldatx'));
ids=Simulink.sdi.getAllRunIDs;
fprintf('RUN_COUNT=%d\n',numel(ids));
manifest=struct('ID',{},'Name',{},'SignalCount',{},'Signals',{});
for k=1:numel(ids)
 r=Simulink.sdi.getRun(ids(k));
 names=cell(r.SignalCount,1);
 for j=1:r.SignalCount, q=r.getSignalByIndex(j); names{j}=q.Name; end
 manifest(k)=struct('ID',ids(k),'Name',r.Name,'SignalCount',r.SignalCount,'Signals',{names});
 fprintf('RUN %g NAME=%s SIGNALS=%d\n',ids(k),r.Name,r.SignalCount);
 match=contains(names,{'WcMap','PRMap','EffMap','NcMap'});
 disp(names(match));
end
save(fullfile(root,'results','component_maps_20261117','inspection.mat'),'manifest','MWS');
fprintf('INSPECTION_COMPLETE\n');

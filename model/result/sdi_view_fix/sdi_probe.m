function sdi_probe
root=fileparts(mfilename('fullpath'));
diary(fullfile(root,'probe.log'));
c=onCleanup(@()diary('off'));
try
base=fileparts(root);
Simulink.sdi.load(fullfile(base,'T700_Dyn_trim1_Open-loop_20261116.mldatx'));
r=Simulink.sdi.Run.getLatest;
fprintf('RUN %s id=%g\n',r.Name,r.ID);
prefix=sprintf('While Iterator\nSubsystem:3.FlowError.');
names={'CompNerr','GGTNerr','FPTNerr','NozNerr'};
ids=zeros(1,4);
for k=1:4
 a=getSignalIDsByName(r,[prefix names{k}]);
 assert(numel(a)==1,'Missing or duplicate signal'); ids(k)=a;
 s=Simulink.sdi.getSignal(a);
 fprintf('SIG id=%g name=%s checked=%g\n',a,strrep(s.Name,newline,'<NL>'),s.Checked);
end
Simulink.sdi.clearAllSubPlots;
Simulink.sdi.loadView(fullfile(base,'T700_Dyn_Error.mldatx'));
check(ids,'ORIGINAL_VIEW');
Simulink.sdi.clearAllSubPlots;
Simulink.sdi.setSubPlotLayout(2,2);
pos=[1 1;1 2;2 1;2 2];
for k=1:4
 s=Simulink.sdi.getSignal(ids(k)); plotOnSubPlot(s,pos(k,1),pos(k,2),true);
end
check(ids,'MANUAL_BIND');
Simulink.sdi.saveView(fullfile(root,'fresh_Error.mldatx'));
Simulink.sdi.save(fullfile(root,'fresh_Error_session.mldatx'));
Simulink.sdi.clearAllSubPlots;
Simulink.sdi.loadView(fullfile(root,'fresh_Error.mldatx'));
check(ids,'FRESH_VIEW');
fprintf('PROBE_COMPLETE\n');
catch err
 disp(getReport(err,'extended','hyperlinks','off'));
end
end
function check(ids,label)
v=zeros(size(ids));
for j=1:numel(ids), s=Simulink.sdi.getSignal(ids(j));v(j)=s.Checked;end
fprintf('%s checked=%s\n',label,mat2str(v));
end

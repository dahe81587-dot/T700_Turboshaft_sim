function sdi_probe2
root=fileparts(mfilename('fullpath')); diary(fullfile(root,'probe2.log')); c=onCleanup(@()diary('off'));
try
Simulink.sdi.load(fullfile(fileparts(root),'T700_Dyn_trim1_Open-loop_20261116.mldatx'));
r=Simulink.sdi.Run.getLatest;
prefix=sprintf('While Iterator\nSubsystem:3.FlowError.'); names={'CompNerr','GGTNerr','FPTNerr','NozNerr'};
ids=zeros(1,4);for k=1:4, ids(k)=getSignalIDsByName(r,[prefix names{k}]);end
modes={'fresh_Error','no_block','no_leaf','name_only','no_newline','entity_newline'};
for k=1:numel(modes)
 Simulink.sdi.clearAllSubPlots; Simulink.sdi.loadView(fullfile(root,[modes{k} '.mldatx'])); check(ids,modes{k});
end
s=Simulink.sdi.getSignal(getSignalIDsByName(r,'GGT_Nmech'));
Simulink.sdi.clearAllSubPlots; Simulink.sdi.setSubPlotLayout(1,1);plotOnSubPlot(s,1,1,true);
Simulink.sdi.saveView(fullfile(root,'direct.mldatx'));
Simulink.sdi.clearAllSubPlots;Simulink.sdi.loadView(fullfile(root,'direct.mldatx'));fprintf('DIRECT checked=%d\n',s.Checked);
s=Simulink.sdi.getSignal(ids(1));s.Name='CompNerr';
Simulink.sdi.clearAllSubPlots;plotOnSubPlot(s,1,1,true);Simulink.sdi.saveView(fullfile(root,'renamed.mldatx'));
Simulink.sdi.clearAllSubPlots;Simulink.sdi.loadView(fullfile(root,'renamed.mldatx'));fprintf('RENAMED checked=%d\n',s.Checked);
fprintf('PROBE2_COMPLETE\n');
catch err,disp(getReport(err,'extended','hyperlinks','off'));end
end
function check(ids,label)
v=zeros(size(ids));for j=1:numel(ids),s=Simulink.sdi.getSignal(ids(j));v(j)=s.Checked;end
fprintf('%s checked=%s\n',label,mat2str(v));
end

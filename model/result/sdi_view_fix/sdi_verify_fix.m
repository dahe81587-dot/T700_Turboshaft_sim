function sdi_verify_fix
root=fileparts(mfilename('fullpath'));base=fileparts(root);
addpath(fullfile(fileparts(base)));
diary(fullfile(root,'verification.log'));c=onCleanup(@()diary('off'));
report=struct('Version',version,'Cases',[],'Passed',false);
try
files={'T700_Dyn_Error.mldatx','T700_Dyn_Gas.mldatx','T700_Dyn_shaft.mldatx'};
prefix=sprintf('While Iterator\nSubsystem:3.');
expected={{[prefix 'FlowError.CompNerr'],[prefix 'FlowError.GGTNerr'],[prefix 'FlowError.FPTNerr'],[prefix 'FlowError.NozNerr']}, ...
 {[prefix 'StationData.S3.Pt'],[prefix 'StationData.S3.Tt'],[prefix 'StationData.S41.Pt'],[prefix 'StationData.S41.Tt'],[prefix 'StationData.S45.Pt'],[prefix 'StationData.S45.Tt'],[prefix 'StationData.S49.Pt'],[prefix 'StationData.S49.Tt']}, ...
 {[prefix 'Wf'],'Qload',[prefix 'Speed.GGTNmech'],[prefix 'Speed.FPTNmech'],[prefix 'Speed.GGTNdot'],[prefix 'Speed.FPTNdot']}};
for cycle=1:2
 if cycle==2,Simulink.sdi.clear;end
 Simulink.sdi.load(fullfile(base,'T700_Dyn_trim1_Open-loop_20261116.mldatx'));
 r=Simulink.sdi.Run.getLatest;
 for k=1:numel(files)
  Simulink.sdi.clearAllSubPlots;
  Simulink.sdi.loadView(fullfile(base,files{k}));
  names=expected{k};shown=false(size(names));ids=zeros(size(names));
  for j=1:numel(names)
   id=getSignalIDsByName(r,names{j});assert(numel(id)==1,'Missing or duplicate signal: %s',names{j});ids(j)=id;
   s=Simulink.sdi.getSignal(id);shown(j)=s.Checked;
  end
  assert(all(shown),'Not all expected signals restored in %s',files{k});
  item=struct('Cycle',cycle,'File',files{k},'RunID',r.ID,'SignalCount',numel(names),'Restored',sum(shown),'Passed',all(shown));
  report.Cases=[report.Cases item];
  fprintf('PASS cycle=%d file=%s restored=%d/%d runID=%g\n',cycle,files{k},sum(shown),numel(names),r.ID);
  Simulink.sdi.save(fullfile(root,sprintf('verified_%d_%s',cycle,files{k})));
 end
 if cycle==1
  helperFile=fullfile(root,'helper_saved_shaft.mldatx');T700_save_view(helperFile);
  Simulink.sdi.clearAllSubPlots;Simulink.sdi.loadView(helperFile);
  for id=ids,s=Simulink.sdi.getSignal(id);assert(s.Checked,'Helper round-trip failed');end
  fprintf('PASS helper_save_roundtrip=%d\n',numel(ids));
 end
end
% Verify the helper also round-trips the four error signals.
Simulink.sdi.loadView(fullfile(base,files{1}));
helperFile=fullfile(root,'helper_saved_Error.mldatx');T700_save_view(helperFile);
Simulink.sdi.clearAllSubPlots;Simulink.sdi.loadView(helperFile);
for j=1:numel(expected{1}),id=getSignalIDsByName(r,expected{1}{j});s=Simulink.sdi.getSignal(id);assert(s.Checked);end
fprintf('PASS helper_error_roundtrip=4\n');
report.Passed=true;
catch err
 report.Error=getReport(err,'extended','hyperlinks','off');disp(report.Error);
end
fid=fopen(fullfile(root,'verification_report.json'),'w','n','UTF-8');fwrite(fid,jsonencode(report,PrettyPrint=true),'char');fclose(fid);
fprintf('VERIFICATION_COMPLETE passed=%d\n',report.Passed);
assert(report.Passed,'View verification failed.');
end

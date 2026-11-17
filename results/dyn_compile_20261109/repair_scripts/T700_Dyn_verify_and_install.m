root=fileparts(fileparts(mfilename('fullpath')));
resultDir=fullfile(root,'results','dyn_compile_20261109');
modelDir=fullfile(root,'model');
addpath(modelDir,fullfile(root,'checks'));
diary(fullfile(resultDir,'final_validation.txt'));
T700_Dyn_initialize('ballin_trim1');
candidate=fullfile(resultDir,'candidate','T700_Dyn.mdl');
report=T700_Dyn_check(candidate);
assert(report.FiniteTimeseriesChecked>50,'动态日志有限值检查覆盖不足。');
save(fullfile(resultDir,'verification_report.mat'),'report');
file=fopen(fullfile(resultDir,'verification_report.json'),'w','n','UTF-8');
fprintf(file,'%s',jsonencode(report,PrettyPrint=true)); fclose(file);
close_system('T700_Dyn',0);
backupDir=fullfile(resultDir,'before');
if ~isfolder(backupDir), mkdir(backupDir); end
target=fullfile(modelDir,'T700_Dyn.mdl');
backup=fullfile(backupDir,'T700_Dyn.mdl');
assert(~isfile(backup),'T700:Dyn:BackupExists','已有修复前备份，停止重复安装。');
copyfile(target,backup);
try
    copyfile(candidate,target,'f');
    load_system(target);
    set_param('T700_Dyn','SimulationCommand','update');
    fprintf('INSTALLED_MODEL_COMPILE_PASS\n');
catch err
    if bdIsLoaded('T700_Dyn'), close_system('T700_Dyn',0); end
    copyfile(backup,target,'f');
    rethrow(err);
end
% Dynamic initialization is separate; check the original steady model still updates.
load_system(fullfile(modelDir,'T700_SS.mdl'));
set_param('T700_SS','SimulationCommand','update');
fprintf('STEADY_MODEL_COMPILE_PASS\n');
for profile={'ballin_trim1','ballin_trim2','ballin_trim3'}
    T700_Dyn_initialize(profile{1});
end
T700_Dyn_initialize('ballin_trim1');
fprintf('FINAL_CHECKS_PASS\n');
diary off;

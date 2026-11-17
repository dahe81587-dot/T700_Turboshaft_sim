root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
modelDir=fullfile(root,'model');
resultDir=fileparts(mfilename('fullpath'));
addpath(modelDir,fullfile(root,'checks'));
diary(fullfile(resultDir,'installed_fix_check.txt'));
source=fullfile(modelDir,'T700_Dyn.mdl');
load_system(source);
inner=['T700_Dyn/While Iterator' newline 'Subsystem/While Iterator'];
fprintf('BEFORE_MaxIters=%s\n',get_param(inner,'MaxIters'));
backupDir=fullfile(resultDir,'before_MaxIters');
if ~isfolder(backupDir), mkdir(backupDir); end
backup=fullfile(backupDir,'T700_Dyn.mdl');
assert(~isfile(backup),'已有修复前备份，停止重复安装。');
copyfile(source,backup);
set_param(inner,'MaxIters','200');
set_param('T700_Dyn','SimulationCommand','update');
save_system('T700_Dyn');
close_system('T700_Dyn',0);
load_system(source);
assert(strcmp(get_param(inner,'MaxIters'),'200'));
set_param('T700_Dyn','SimulationCommand','update');
fprintf('INSTALLED_MaxIters=%s\nINSTALLED_COMPILE_PASS\n',get_param(inner,'MaxIters'));
close_system('T700_Dyn',0);
% Verify the installed source using the default harness configuration.
report=T700_Dyn_hold_test('ballin_trim1',60,[0.015 0.0075],fullfile(resultDir,'final_trim1'));
assert(report.Passed,'正式模型的无扰动保持测试未通过。');
fprintf('INSTALLED_HOLD_TEST_PASS\n');
diary off;

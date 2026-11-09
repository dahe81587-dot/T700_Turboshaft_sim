% Compatibility script referenced by the original Turboshaft model CloseFcn.
% Removes only the original example setup path; retains all workspace results.
exampleSetupPath=fullfile(fileparts(mfilename('fullpath')),'SimSetup');
if any(strcmpi(strsplit(path,pathsep),exampleSetupPath))
    rmpath(exampleSetupPath);
end
clear exampleSetupPath

function F = T700_stage06c_load
% Load both user-digitized A1 and extracted A2-A11; no model initialization.
processedDir = fileparts(mfilename('fullpath'));
S = load(fullfile(processedDir,'T700_component_functions_raw.mat'),'T700Functions');
F = S.T700Functions;
A1 = load(F.CompressorA1SourceFile,'allRaw');
F.CompressorA1 = A1.allRaw;
names = fieldnames(F.Curves);
for k = 1:numel(names)
    C = F.Curves.(names{k});
    if isfield(C,'PointMatrix')
        C.Points = array2table(C.PointMatrix,'VariableNames', ...
            {'X','Y','XReadingResolution','YReadingResolution','PixelX','PixelY'});
        C.RawRecord = jsondecode(C.SourceRecordJSON);
    end
    F.Curves.(names{k}) = C;
end
fprintf('A1: 11 curves, 66 user-selected points.\n');
fprintf('A2-A11: 10 functions, 106 source points.\n');
fprintf('Total: 21 curves/functions, 172 points.\n');
fprintf('Raw digitization only; model maps have not been replaced.\n');
end

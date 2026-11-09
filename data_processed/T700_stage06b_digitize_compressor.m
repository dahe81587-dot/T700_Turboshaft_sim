function out = T700_stage06b_digitize_compressor(request)
% Digitize the remaining Ballin Figure A1 corrected-speed curves manually.
% T700_stage06b_digitize_compressor(98)          : select/redo one curve.
% T700_stage06b_digitize_compressor('remaining') : collect missing curves.
% T700_stage06b_digitize_compressor('summary')   : inspect/merge saved data.
% No model, component map, or simulated engine output is modified.

if nargin == 0
    request = 'remaining';
end
projectDir = fileparts(fileparts(mfilename('fullpath')));
rawDir = fullfile(projectDir, 'data_raw', 'compressor');
resultDir = fullfile(projectDir, 'results', 'compressor');
if ~isfolder(resultDir)
    mkdir(resultDir);
end

% These rectangles control image zoom and coarse misclick checks only.
% They are not compressor data or interpolation nodes.
% Columns: NGC percent, original symbol, PR lower/upper, Wc lower/upper.
plan = [ ...
     65  1   2.8  4.2   2.7  3.4
     80  2   5.0  7.2   4.2  5.0
     82  3   5.8  7.8   4.7  5.5
     85  4   6.8  9.2   5.3  6.2
     87  5   7.8 10.6   5.7  6.6
     89  6   8.8 12.0   6.1  7.1
     92  7  10.8 13.8   7.0  8.0
     94  8  12.2 15.2   7.6  8.6
     96  9  13.8 16.7   8.3  9.3
     98 10  15.0 18.2   9.0 10.0
    100 11  15.0 20.0   9.0 11.0];

seedFile = lineFile(rawDir, 100);
assert(isfile(seedFile), 'Complete and verify Stage 06A first.');
seedData = load(seedFile, 'raw');
seed = seedData.raw;
assert(isfield(seed, 'ScriptVersion') && seed.ScriptVersion == 2, ...
    'The approved Stage 06A V2 calibration is required.');
H = seed.PixelToDataMatrix;
assert(isequal(size(H), [3 3]) && ...
    max(abs(H(:,3)-[0;0;1])) < 1e-12, 'Invalid affine calibration.');
imageFile = fullfile(rawDir, 'T700_Compressor_A1_original.png');
imageData = imread(imageFile);
assert(isequal(size(imageData), seed.Source.ImageSize), ...
    'Use the same unmodified source PNG as Stage 06A.');

if ischar(request) || isstring(request)
    action = char(request);
    switch lower(action)
        case 'remaining'
            for row = 10:-1:1
                nc = plan(row,1);
                if lineReady(rawDir, resultDir, nc, H)
                    fprintf('Keeping completed curve: %g%% NGC\n', nc);
                else
                    T700_stage06b_digitize_compressor(nc);
                end
            end
            out = summarize(rawDir, resultDir, plan, seed, imageData);
        case 'summary'
            out = summarize(rawDir, resultDir, plan, seed, imageData);
        otherwise
            error('Use a speed percentage, ''remaining'', or ''summary''.');
    end
    return
end

assert(isnumeric(request) && isscalar(request) && isfinite(request), ...
    'Enter one numeric corrected-speed percentage.');
idx = find(plan(:,1) == request, 1);
assert(~isempty(idx) && request ~= 100, ...
    'Supported: 65,80,82,85,87,89,92,94,96,98. Keep Stage 06A for 100.');
nc = plan(idx,1);
symbol = plan(idx,2);
roi = plan(idx,3:6);
name = sprintf('stage06b_compressor_N%03d', nc);
diary(fullfile(resultDir, [name '_check.txt']));
stopDiary = onCleanup(@() diary('off'));
fprintf('\nSTAGE06B_CURVE_RUN %s, NGC = %g%%, symbol = %d\n', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), nc, symbol);

fig = taskFigure('T700_Stage06B_Select', 'T700 A1 - select one speed curve');
ax = axes('Parent', fig);
image(ax, imageData);
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
hold(ax, 'on');
corners = [roi(1) roi(3) 1; roi(2) roi(3) 1; ...
    roi(1) roi(4) 1; roi(2) roi(4) 1] / H;
xlim(ax, [min(corners(:,1)) max(corners(:,1))]);
ylim(ax, [min(corners(:,2)) max(corners(:,2))]);

selectedPixels = nan(6,2);
for k = 1:6
    title(ax, {sprintf('%g%% NGC, original symbol %d: click point %d / 6', ...
        nc, symbol, k), ...
        'LEFT TO RIGHT on the short solid curve. Include both ends.', ...
        'Exclude long horizontal extensions, dotted lines, and label strokes.'});
    drawnow;
    figure(fig);
    axes(ax); %#ok<LAXES>
    [x,y] = ginput(1);
    assert(isscalar(x), ...
        'Selection cancelled. Run ''remaining'' to resume saved curves.');
    selectedPixels(k,:) = [x y];
    plot(ax, x, y, 'ro', 'MarkerSize', 7, 'LineWidth', 1.2);
    text(ax, x+5, y, sprintf(' %d', k), 'Color', 'r', 'FontSize', 11);
end

xy = [selectedPixels ones(6,1)] * H(:,1:2);
assert(all(isfinite(xy(:))), 'Invalid selected coordinates.');
assert(all(diff(xy(:,1)) > 0), 'Select points in increasing pressure ratio.');
assert(all(xy(:,1) >= roi(1) & xy(:,1) <= roi(2)) && ...
    all(xy(:,2) >= roi(3) & xy(:,2) <= roi(4)), ...
    'Points outside this curve''s zoom region. Check the original symbol.');
Point = (1:6)';
NGC_percent = nc*ones(6,1);
PRstatic = xy(:,1);
Wc_lbm_s = xy(:,2);

raw = struct;
raw.Source = seed.Source;
raw.NGC_percent = nc;
raw.OriginalSymbol = symbol;
raw.PressureRatioDefinition = seed.PressureRatioDefinition;
raw.FlowUnit = seed.FlowUnit;
raw.CalibrationTargets = seed.CalibrationTargets;
raw.CalibrationPixels = seed.CalibrationPixels;
raw.CalibrationMethod = seed.CalibrationMethod;
raw.PixelToDataMatrix = H;
raw.FrameFitError = seed.FrameFitError;
raw.SelectedPixels = selectedPixels;
raw.Points = table(Point, NGC_percent, PRstatic, Wc_lbm_s);
raw.Created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
raw.DigitizationOnly = true;
raw.SimulationRun = false;
raw.DigitizerRevision = 'Stage06B-v1';
rawFile = lineFile(rawDir, nc);
backupMat(rawFile);
save(rawFile, 'raw');
exportgraphics(fig, fullfile(resultDir, [name '_overlay.png']), 'Resolution', 200);

fig2 = taskFigure('T700_Stage06B_Points', 'T700 A1 - selected raw points');
ax2 = axes('Parent', fig2);
plot(ax2, PRstatic, Wc_lbm_s, 'o-', 'LineWidth', 1.2);
grid(ax2, 'on');
xlim(ax2, roi(1:2));
ylim(ax2, roi(3:4));
xlabel(ax2, 'Compressor static pressure ratio, Ps3/Pt2');
ylabel(ax2, 'Corrected mass flow, Wc [lbm/s]');
title(ax2, sprintf('Ballin Fig. A1: %g%% NGC, symbol %d, six raw points', nc, symbol));
exportgraphics(fig2, fullfile(resultDir, [name '_points.png']), 'Resolution', 200);
disp(raw.Points);
fprintf('Raw points saved: %s\n', rawFile);
fprintf('STAGE06B_N%03d_RAW_POINTS_SAVED\n', nc);
out = raw;
end

function path = lineFile(rawDir, nc)
path = fullfile(rawDir, sprintf('T700_compressor_A1_N%03d_raw.mat', nc));
end

function ok = validLine(raw, nc, H)
ok = isfield(raw, 'Points') && istable(raw.Points) && ...
    height(raw.Points) == 6 && ...
    all(ismember({'Point','NGC_percent','PRstatic','Wc_lbm_s'}, ...
        raw.Points.Properties.VariableNames));
if ~ok
    return
end
ok = all(raw.Points.NGC_percent == nc) && ...
    all(isfinite(raw.Points.PRstatic)) && all(isfinite(raw.Points.Wc_lbm_s)) && ...
    all(diff(raw.Points.PRstatic) > 0) && ...
    isfield(raw, 'SelectedPixels') && isequal(size(raw.SelectedPixels), [6 2]) && ...
    isfield(raw, 'PixelToDataMatrix') && ...
    isequal(raw.PixelToDataMatrix, H) && ...
    strcmp(raw.PressureRatioDefinition, 'Ps3/Pt2') && strcmp(raw.FlowUnit, 'lbm/s');
end

function ok = lineReady(rawDir, resultDir, nc, H)
ok = false;
path = lineFile(rawDir, nc);
if ~isfile(path)
    return
end
data = load(path, 'raw');
if ~isfield(data, 'raw') || ~validLine(data.raw, nc, H)
    return
end
name = sprintf('stage06b_compressor_N%03d', nc);
ok = isfile(fullfile(resultDir, [name '_overlay.png'])) && ...
    isfile(fullfile(resultDir, [name '_points.png']));
end

function report = summarize(rawDir, resultDir, plan, seed, imageData)
diary(fullfile(resultDir, 'stage06b_compressor_all_check.txt'));
stopDiary = onCleanup(@() diary('off'));
fprintf('\nSTAGE06B_SUMMARY %s\n', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
counts = zeros(11,1);
lines = cell(11,1);
for k = 1:11
    path = lineFile(rawDir, plan(k,1));
    if isfile(path)
        data = load(path, 'raw');
        if isfield(data, 'raw') && validLine(data.raw, plan(k,1), seed.PixelToDataMatrix)
            lines{k} = data.raw;
            counts(k) = 6;
        end
    end
end
report.Status = table(plan(:,1), plan(:,2), counts, ...
    'VariableNames', {'NGC_percent','OriginalSymbol','PointCount'});
report.Complete = all(counts == 6);
report.DigitizationOnly = true;
report.SimulationRun = false;
disp(report.Status);
if ~report.Complete
    fprintf('STAGE06B_A1_RAW_POINTS_INCOMPLETE\n');
    return
end

allRaw = struct;
allRaw.Source = seed.Source;
allRaw.NGC_percent = plan(:,1);
allRaw.Lines = lines;
allRaw.Points = seed.Points([],:);
for k = 1:11
    allRaw.Points = [allRaw.Points; lines{k}.Points];
end
allRaw.PressureRatioDefinition = seed.PressureRatioDefinition;
allRaw.FlowUnit = seed.FlowUnit;
allRaw.CalibrationMethod = seed.CalibrationMethod;
allRaw.PixelToDataMatrix = seed.PixelToDataMatrix;
allRaw.DigitizationOnly = true;
allRaw.RectangularMapCreated = false;
allRaw.SimulationRun = false;
allRaw.Created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
file = fullfile(rawDir, 'T700_compressor_A1_all_raw.mat');
backupMat(file);
save(file, 'allRaw');

fig = taskFigure('T700_Stage06B_AllOverlay', 'T700 A1 - all raw points on source');
ax = axes('Parent', fig);
image(ax, imageData);
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
hold(ax, 'on');
xlim(ax, [300 2190]);
ylim(ax, [280 2500]);
colors = jet(11);
for k = 1:11
    p = lines{k}.SelectedPixels;
    plot(ax, p(:,1), p(:,2), 'o', 'Color', colors(k,:), ...
        'MarkerSize', 4, 'LineWidth', 0.9);
end
title(ax, 'Ballin Fig. A1: 11 speed curves, 66 raw selected points');
exportgraphics(fig, fullfile(resultDir, ...
    'stage06b_compressor_all_overlay.png'), 'Resolution', 200);

fig2 = taskFigure('T700_Stage06B_AllPoints', 'T700 A1 - all speed curves');
ax2 = axes('Parent', fig2);
hold(ax2, 'on');
for k = 1:11
    t = lines{k}.Points;
    plot(ax2, t.PRstatic, t.Wc_lbm_s, 'o-', 'Color', colors(k,:), ...
        'LineWidth', 1.1, 'MarkerSize', 4, ...
        'DisplayName', sprintf('%g%%', plan(k,1)));
end
grid(ax2, 'on');
xlim(ax2, [0 20]);
ylim(ax2, [2 12]);
xlabel(ax2, 'Compressor static pressure ratio, Ps3/Pt2');
ylabel(ax2, 'Corrected mass flow, Wc [lbm/s]');
title(ax2, 'Ballin Fig. A1: raw short-curve segments, no fitting');
legend(ax2, 'show', 'Location', 'eastoutside');
exportgraphics(fig2, fullfile(resultDir, ...
    'stage06b_compressor_all_points.png'), 'Resolution', 200);

report.RawFile = file;
report.CurveCount = 11;
report.PointCount = height(allRaw.Points);
fprintf('Curve count: 11\nPoint count: %d\n', report.PointCount);
fprintf('Rectangular map created: 0\nSimulation run: 0\n');
fprintf('STAGE06B_A1_ALL_RAW_POINTS_SAVED\n');
end

function fig = taskFigure(tag, name)
fig = findall(groot, 'Type', 'figure', 'Tag', tag);
if isempty(fig)
    fig = figure('Tag', tag, 'Name', name, 'NumberTitle', 'off', ...
        'Units', 'normalized', 'Position', [0.08 0.08 0.84 0.84], ...
        'Color', 'w', 'WindowStyle', 'normal');
else
    fig = fig(1);
    clf(fig);
    figure(fig);
end
end

function backupMat(file)
if isfile(file)
    [folder,name,ext] = fileparts(file);
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    copyfile(file, fullfile(folder, [name '_' stamp ext]));
end
end

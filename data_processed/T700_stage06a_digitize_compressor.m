function raw = T700_stage06a_digitize_compressor
% Version 2: fixed calibration of the supplied, unmodified Figure A1 PNG.
% The user selects six curve points; no manual corner calibration is needed.
% This function does not edit, initialize, or run a Simulink model.
% Requires base MATLAB only; all engineering points are selected by the user.

processedDir = fileparts(mfilename('fullpath'));
projectDir = fileparts(processedDir);
rawDir = fullfile(projectDir, 'data_raw', 'compressor');
resultDir = fullfile(projectDir, 'results', 'compressor');
imageFile = fullfile(rawDir, 'T700_Compressor_A1_original.png');
assert(isfile(imageFile), 'Source image missing: %s', imageFile);
sourceImage = imread(imageFile);
assert(size(sourceImage,1) == 3168 && size(sourceImage,2) == 2440, ...
    'Use the original 2440-by-3168 PNG. This calibration is image-specific.');
if ~isfolder(resultDir)
    mkdir(resultDir);
end

diary(fullfile(resultDir, 'stage06a_compressor_N100_check.txt'));
stopDiary = onCleanup(@() diary('off'));
fprintf('\nSTAGE06A_V2_RUN %s\n', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

% Raster locations of the PRINTED plot-frame corners in the supplied PNG.
% These are image geometry, not compressor curve data. Row order: A,B,C,D.
pixels = [438 2399; 2029 2410; 437 389; 2029 393];
targets = [0 2; 20 2; 0 12; 20 12];
B = [pixels ones(4,1)];
affine = B \ targets;
H = [affine [0;0;1]];
frameFitError = B*affine - targets;
maxFrameError = max(abs(frameFitError), [], 1);
assert(maxFrameError(1) < 0.05 && maxFrameError(2) < 0.05, ...
    'Printed-frame calibration fit failed.');
fprintf('Fixed printed-frame fit error: PR = %.5f, Wc = %.5f lbm/s\n', ...
    maxFrameError(1), maxFrameError(2));

fig = figure('Name', 'T700 Figure A1 - manual digitization', ...
    'NumberTitle', 'off', 'Units', 'normalized', ...
    'Position', [0.08 0.08 0.84 0.84], 'Color', 'w', ...
    'WindowStyle', 'normal');
ax = axes('Parent', fig);
image(ax, sourceImage);
axis(ax, 'image');
axis(ax, 'off');
set(ax, 'YDir', 'reverse');
hold(ax, 'on');

labels = {'A (0,2)', 'B (20,2)', 'C (0,12)', 'D (20,12)'};
for k = 1:4
    plot(ax, pixels(k,1), pixels(k,2), 'bo', ...
        'MarkerSize', 10, 'LineWidth', 1.5);
    text(ax, pixels(k,1)+15, pixels(k,2)-25, labels{k}, ...
        'Color', 'b', 'FontSize', 11, 'Interpreter', 'none');
end
xlim(ax, [300 2190]);
ylim(ax, [280 2500]);
title(ax, 'V2: fixed calibration uses the PRINTED plot frame, not page corners');
exportgraphics(fig, fullfile(resultDir, ...
    'stage06a_compressor_N100_calibration.png'), 'Resolution', 200);

% Zoom into the original upper-right map region without changing coordinates.
corners = [15 9 1; 20 9 1; 15 11 1; 20 11 1] / H;
xlim(ax, [min(corners(:,1)) max(corners(:,1))]);
ylim(ax, [min(corners(:,2)) max(corners(:,2))]);
title(ax, {'V2: click 6 points LEFT TO RIGHT on the TOP short curve marked 11', ...
    'First = left curve start; sixth = right curve end. Exclude long flat extensions.'});
drawnow;

selectedPixels = nan(6,2);
for k = 1:6
    figure(fig);
    axes(ax); %#ok<LAXES>
    [x,y] = ginput(1);
    assert(isscalar(x), 'Selection cancelled. Run the function again.');
    selectedPixels(k,:) = [x y];
    plot(ax, x, y, 'ro', 'MarkerSize', 7, 'LineWidth', 1.2);
    text(ax, x+8, y, sprintf(' %d',k), 'Color', 'r', 'FontSize', 11);
end

xy = [selectedPixels ones(6,1)] * affine;
PRstatic = xy(:,1);
Wc_lbm_s = xy(:,2);
assert(all(isfinite(xy(:))), 'Non-finite digitized coordinates.');
assert(all(diff(PRstatic) > 0), 'Select points in increasing pressure ratio.');
assert(all(PRstatic > 16 & PRstatic < 19.5) && ...
    all(Wc_lbm_s > 9.7 & Wc_lbm_s < 10.3), ...
    'Points outside the 100-percent curve region. Select the TOP curve marked 11.');

Point = (1:6)';
NGC_percent = 100*ones(6,1);
points = table(Point, NGC_percent, PRstatic, Wc_lbm_s);
raw = struct;
raw.Source.Report = 'NASA-TM-100991, Ballin, 1988';
raw.Source.Figure = 'A1';
raw.Source.PDFPage = 56;
raw.Source.PrintedPage = 42;
raw.Source.Engine = 'Public T700 reference model';
raw.Source.PDF = fullfile(projectDir, 'sources', ...
    'A_high_fidelity_real-time_simulation_of_a_small_tu.pdf');
raw.Source.Image = imageFile;
raw.PressureRatioDefinition = 'Ps3/Pt2';
raw.FlowUnit = 'lbm/s';
raw.CalibrationTargets = targets;
raw.CalibrationPixels = pixels;
raw.CalibrationMethod = 'Fixed printed-frame raster corners; four-point affine fit';
raw.Source.ImageSize = size(sourceImage);
raw.PixelToDataMatrix = H;
raw.FrameFitError = frameFitError;
raw.SelectedPixels = selectedPixels;
raw.Points = points;
raw.Created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
raw.DigitizationOnly = true;
raw.SimulationRun = false;
raw.ScriptVersion = 2;

rawFile = fullfile(rawDir, 'T700_compressor_A1_N100_raw.mat');
if isfile(rawFile)
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    backupFile = fullfile(rawDir, ['T700_compressor_A1_N100_raw_' stamp '.mat']);
    copyfile(rawFile, backupFile);
    fprintf('Previous raw points backed up: %s\n', backupFile);
end
save(rawFile, 'raw');

exportgraphics(fig, fullfile(resultDir, ...
    'stage06a_compressor_N100_overlay.png'), 'Resolution', 200);

fig2 = figure('Name', 'T700 100% NGC - raw digitized points', ...
    'NumberTitle', 'off', 'Color', 'w');
ax2 = axes('Parent', fig2);
plot(ax2, PRstatic, Wc_lbm_s, 'o-', 'LineWidth', 1.2);
grid(ax2, 'on');
xlim(ax2, [15 20]);
ylim(ax2, [9 11]);
xlabel(ax2, 'Compressor static pressure ratio, Ps3/Pt2');
ylabel(ax2, 'Corrected mass flow, Wc [lbm/s]');
title(ax2, 'Ballin Fig. A1, 100% NGC: six raw points (V2 calibration)');
exportgraphics(fig2, fullfile(resultDir, ...
    'stage06a_compressor_N100_points.png'), 'Resolution', 200);

disp(points);
fprintf('Raw points saved: %s\n', rawFile);
fprintf('Point count: 6\nMap replacement: 0\nSimulation run: 0\n');
fprintf('STAGE06A_N100_RAW_POINTS_SAVED\n');
end

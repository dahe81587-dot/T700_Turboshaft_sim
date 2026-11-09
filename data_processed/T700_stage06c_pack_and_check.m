function report = T700_stage06c_pack_and_check
% Package the extracted A2-A11 raster data and verify the saved MAT/QA plots.
% This function neither initializes nor runs a Simulink model.

projectDir = fileparts(fileparts(mfilename('fullpath')));
rawDir = fullfile(projectDir, 'data_raw', 'component_functions');
resultDir = fullfile(projectDir, 'results', 'component_functions');
assert(isfolder(rawDir), 'Run T700_stage06c_extract_remaining.py first.');
if ~isfolder(resultDir)
    mkdir(resultDir);
end
diary(fullfile(resultDir, 'stage06c_remaining_curves_check.txt'));
stopDiary = onCleanup(@() diary('off'));

manifestFile = fullfile(projectDir, 'data_processed', ...
    'T700_remaining_functions_manifest.json');
manifest = jsondecode(fileread(manifestFile));
assert(manifest.extraction_complete && manifest.curve_count == 10);

a1File = fullfile(projectDir, 'data_raw', 'compressor', ...
    'T700_compressor_A1_all_raw.mat');
a1 = load(a1File, 'allRaw');
assert(numel(a1.allRaw.Lines) == 11 && height(a1.allRaw.Points) == 66);

T700Functions = struct;
T700Functions.SourceReport = 'NASA-TM-100991, Ballin, 1988';
T700Functions.SourcePDF = manifest.source_pdf;
T700Functions.SourcePDF_SHA256 = manifest.source_pdf_sha256;
T700Functions.Engine = 'Ballin public T700 reference model';
T700Functions.CompressorA1 = a1.allRaw;
T700Functions.CompressorA1SourceFile = a1File;
T700Functions.RawDigitizationOnly = true;
T700Functions.MapsAppliedToModel = false;
T700Functions.SimulationRun = false;

figures = strings(10,1);
counts = zeros(10,1);
ranges = zeros(10,4);
resolution = zeros(10,2);
tickError = zeros(10,2);
currentSteady = false(10,1);

for j = 1:10
    number = j+1;
    key = sprintf('A%02d', number);
    R = jsondecode(fileread(fullfile(rawDir, ['T700_' key '_raw.json'])));
    p = R.points;
    assert(size(p,2) == 6 && size(p,1) == R.point_count);
    assert(all(isfinite(p), 'all') && all(diff(p(:,1)) > 0));
    assert(all(p(:,3:4) > 0, 'all'));
    assert(all(R.marker_arm_support >= 0.4));

    H = R.calibration.pixel_to_data_homography;
    q = [p(:,5:6) ones(size(p,1),1)] * H';
    reprojected = q(:,1:2)./q(:,3);
    assert(max(abs(reprojected-p(:,1:2)), [], 'all') < 1e-9, ...
        'Pixel-coordinate transform mismatch in %s.', key);

    I = imread(R.source_image);
    gray = mean(double(I),3);
    for k = 1:size(p,1)
        x = round(p(k,5)); y = round(p(k,6));
        assert(min(gray(y-3:y+3,x-3:x+3), [], 'all') < 160, ...
            'Selected point does not touch source ink: %s point %d.', key, k);
    end
    checks = R.calibration.independent_tick_checks;
    tickError(j,:) = abs([checks(1).error checks(2).error]);
    bounds = reshape(R.plot_bounds,1,[]);
    assert(tickError(j,1) < .01*(bounds(2)-bounds(1)));
    assert(tickError(j,2) < .01*(bounds(4)-bounds(3)));

    C = struct;
    C.Figure = R.figure;
    C.Definition = R.definition;
    C.XName = R.x_name;
    C.YName = R.y_name;
    C.XUnit = R.x_unit;
    C.YUnit = R.y_unit;
    C.X = p(:,1);
    C.Y = p(:,2);
    C.Points = array2table(p, 'VariableNames', ...
        {'X','Y','XReadingResolution','YReadingResolution','PixelX','PixelY'});
    C.UseForCurrentSteady = R.use_for_current_steady;
    C.RawRecord = R;
    if number == 6
        C.ConstantEstimate = R.constant_estimate;
        assert(max(C.Y)-min(C.Y) < 2*max(p(:,4)));
    end
    if number == 8
        assert(any(C.Y < 0), 'Preserve the source negative tail in A8.');
    end
    T700Functions.Curves.(key) = C;
    figures(j) = R.figure;
    counts(j) = R.point_count;
    ranges(j,:) = [min(C.X) max(C.X) min(C.Y) max(C.Y)];
    resolution(j,:) = max(p(:,3:4), [], 1);
    currentSteady(j) = R.use_for_current_steady;

    % Source overlay: the selected markers are shown without changing the raster.
    f = figure('Visible','off','Color','w','Units','pixels', ...
        'Position',[20 20 900 1050]);
    closeF = onCleanup(@() close(f));
    ax = axes('Parent',f);
    image(ax,I);
    axis(ax,'image'); axis(ax,'off');
    set(ax,'YDir','reverse'); hold(ax,'on');
    plot(ax,p(:,5),p(:,6),'ro','MarkerSize',6,'LineWidth',1.1);
    for k = 1:size(p,1)
        text(ax,p(k,5)+14,p(k,6)-8,sprintf('%d',k), ...
            'Color','r','FontSize',8);
    end
    frame = R.calibration.frame_pixels;
    plot(ax,frame(:,1),frame(:,2),'bo','MarkerSize',7,'LineWidth',1.1);
    for k = 1:numel(checks)
        v = checks(k).pixel;
        plot(ax,v(1),v(2),'gs','MarkerSize',7,'LineWidth',1.1);
    end
    xlim(ax,[min(frame(:,1))-240 max(frame(:,1))+140]);
    ylim(ax,[min(frame(:,2))-80 max(frame(:,2))+190]);
    title(ax,{sprintf('Ballin Fig. %s: %s',R.figure,R.function_title), ...
        'Red: extracted points; blue: printed frame; green: independent tick check'}, ...
        'Interpreter','none','FontSize',10);
    exportgraphics(f,fullfile(resultDir,['T700_' key '_overlay.png']), ...
        'Resolution',180);
    clear closeF

    f = figure('Visible','off','Color','w','Units','pixels', ...
        'Position',[20 20 900 650]);
    closeF = onCleanup(@() close(f));
    ax = axes('Parent',f);
    plot(ax,C.X,C.Y,'o-','LineWidth',1.2,'MarkerSize',5);
    grid(ax,'on');
    dx = .008*(bounds(2)-bounds(1));
    dy = .008*(bounds(4)-bounds(3));
    xlim(ax,bounds(1:2)+[-dx dx]);
    ylim(ax,bounds(3:4)+[-dy dy]);
    xlabel(ax,sprintf('%s [%s]',C.XName,C.XUnit),'Interpreter','none');
    ylabel(ax,sprintf('%s [%s]',C.YName,C.YUnit),'Interpreter','none');
    title(ax,{sprintf('Ballin Fig. %s: %s',R.figure,R.function_title), ...
        'Digitized source points; connecting segments are for viewing only'}, ...
        'Interpreter','none');
    exportgraphics(f,fullfile(resultDir,['T700_' key '_points.png']), ...
        'Resolution',180);
    clear closeF
    fprintf('%s: %d source points; pixel projection and tick checks passed.\n', ...
        key, counts(j));
end

T700Functions.RemainingCurveCount = 10;
T700Functions.RemainingPointCount = sum(counts);
T700Functions.TotalCurveCount = 21;
T700Functions.TotalPointCount = 66+sum(counts);
T700Functions.ConventionNotes = {
    'A9: original figure abscissa Ps9/P45 differs from Eq.33 P49/P45.'
    'A9: flow parameter and printed LBM/SEC unit need conversion before T-MATS use.'
    'A10: original Ps9/P49 label is opposite to Eq.38; keep f10 neutral until boundary conversion.'
    'A8: negative source tail retained; admissible turbine-map domain is a later decision.'
    'A11: optional heat-sink coefficient recorded; no additional dynamic state enabled.'
    'Raster reading resolution is not experimental uncertainty.'
};
T700Functions.Summary = table(figures,counts,ranges(:,1),ranges(:,2), ...
    ranges(:,3),ranges(:,4),resolution(:,1),resolution(:,2), ...
    tickError(:,1),tickError(:,2),currentSteady, ...
    'VariableNames',{'Figure','PointCount','XMin','XMax','YMin','YMax', ...
    'MaxXReadingResolution','MaxYReadingResolution','XTickError', ...
    'YTickError','UseForCurrentSteady'});
assert(T700Functions.RemainingPointCount == 106);

matFile = fullfile(projectDir,'data_processed','T700_component_functions_raw.mat');
save(matFile,'T700Functions','-v7');
roundTrip = load(matFile,'T700Functions');
for j = 1:10
    key = sprintf('A%02d',j+1);
    assert(isequal(roundTrip.T700Functions.Curves.(key).Points, ...
        T700Functions.Curves.(key).Points));
end
writetable(T700Functions.Summary,fullfile(resultDir,'stage06c_curve_summary.csv'));
report = struct('RemainingCurveCount',10,'RemainingPointCount',sum(counts), ...
    'TotalCurveCount',21,'TotalPointCount',66+sum(counts), ...
    'MATRoundTripPassed',true,'PixelReprojectionPassed',true, ...
    'SourceInkChecksPassed',true,'IndependentTickChecksPassed',true, ...
    'VisualReviewIsSeparate',true, ...
    'MapsAppliedToModel',false,'SimulationRun',false,'DataFile',matFile);
save(fullfile(resultDir,'stage06c_remaining_curves_check.mat'),'report');
disp(T700Functions.Summary);
fprintf('Remaining curves: 10\nRemaining points: %d\n',sum(counts));
fprintf('Total curves including A1: 21\nTotal points including A1: %d\n',66+sum(counts));
fprintf('MAT round-trip check: PASS\nMaps applied: 0\nSimulation run: 0\n');
fprintf('STAGE06C_REMAINING_CURVES_PACKAGED\n');
end

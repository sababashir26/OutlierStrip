function OutlierStrip()
% OUTLIERSTRIP - Interactive cosmic-ray detector and manual cleaner for Raman spectra.
%
% Layout:
%   - Top toolbar: variable selection + threshold slider (curvature score) + scrollable stats box.
%   - Top axes: original spectra (MATLAB default multi-colour). Manual clicks -> red (marked).
%   - Middle bar: start/end spectrum + Delete MARKED (affects any manually marked spectrum).
%   - Bottom axes: auto-detected cosmic candidates ONLY (stacked red by default).
%   - Cosmic range bar: Cosmic start / end (index range within cosmic candidates).
%   - Bottom bar: Play/Pause toggle, Show stacked cosmic view, Delete COSMIC candidates,
%                 Movie speed (seconds per frame) slider.
%
% Data:
%   - Select one or more MAT-files with 2D double matrices (spectra).
%   - Optional: select MAT-file with wavenumber vector.
%   - Otherwise: enter wavenumber dimension (e.g. 805).
%   - Cleaned variables are written back to the WORKSPACE only.
%     Original .mat files on disk are untouched.

    % ---------------- Shared state ----------------
    dataVarNames      = {};   % spectra variable names
    selectedVariable  = '';
    currentIndex      = 1;

    currentSpectra    = [];   % [nSpectra x wnDim]
    currentWasTransposed = false;
    xAxis             = [];
    wnDim             = [];
    wnVec             = [];

    nSpectra          = 0;
    startSpectrum     = 1;
    endSpectrum       = 1;

    manualMask        = [];   % logical 1 x nSpectra (manual marks)
    autoCosmicMask    = [];   % logical 1 x nSpectra (auto candidates)
    cosmicScore       = [];   % curvature-based score per spectrum

    threshold         = 80;   % default curvature score threshold
    MAX_PLOTTED_SPECTRA = 800;

    isPlaying         = false; % for movie
    movieDelaySec     = 0.03;  % default movie speed

    % Cosmic range state (indices within list of cosmic candidates)
    cosStart          = 1;
    cosEnd            = 1;

    % UI handles
    f              = [];
    axMain         = [];
    axCosmic       = [];
    varPopup       = [];
    startEdit      = [];
    endEdit        = [];
    thrSlider      = [];
    thrValueLabel  = [];
    statsBox       = [];
    speedSlider    = [];
    speedLabel     = [];
    playPauseBtn   = [];
    cosStartEdit   = [];
    cosEndEdit     = [];

    % ---------------- Step 1: Load spectra from MAT files ----------------
    [files, path] = uigetfile('*.mat', ...
        'Select MAT-file(s) containing spectra variables', ...
        'MultiSelect', 'on');

    if isequal(files, 0)
        return;
    end
    if ischar(files)
        files = {files};
    end

    for k = 1:numel(files)
        fpath = fullfile(path, files{k});
        info = whos('-file', fpath);
        for j = 1:numel(info)
            sz = info(j).size;
            if numel(sz) == 2 && sz(1) > 1 && sz(2) > 1 && strcmp(info(j).class, 'double')
                vname = info(j).name;
                s = load(fpath, vname);
                assignin('base', vname, s.(vname));  % workspace copy
                if ~ismember(vname, dataVarNames)
                    dataVarNames{end+1} = vname; %#ok<AGROW>
                end
            end
        end
    end

    if isempty(dataVarNames)
        errordlg('No 2D double matrices found in selected MAT-files.', ...
                 'No spectra found');
        return;
    end

    % ---------------- Step 2: Optional wavenumber vector ----------------
    choiceWn = questdlg( ...
        'Load a wavenumber vector from a MAT-file? (Recommended)', ...
        'Wavenumber', ...
        'Yes', 'No', 'Yes');

    if strcmp(choiceWn, 'Yes')
        [wfile, wpath] = uigetfile('*.mat', 'Select MAT-file with wavenumber vector');
        if ~isequal(wfile, 0)
            winfo = whos('-file', fullfile(wpath, wfile));
            cand = {};
            for j = 1:numel(winfo)
                sz = winfo(j).size;
                if numel(sz) == 2 && xor(sz(1) > 1, sz(2) > 1) && ...
                        strcmp(winfo(j).class, 'double')
                    cand{end+1} = winfo(j).name; %#ok<AGROW>
                end
            end
            if isempty(cand)
                errordlg('No 1D double vector found in that MAT-file.', ...
                         'No wavenumber found');
            else
                if numel(cand) == 1
                    wnVarName = cand{1};
                else
                    [idx, ok] = listdlg('PromptString', 'Select wavenumber variable:', ...
                                        'SelectionMode', 'single', ...
                                        'ListString', cand);
                    if ~ok
                        wnVarName = '';
                    else
                        wnVarName = cand{idx};
                    end
                end
                if ~isempty(wnVarName)
                    sW = load(fullfile(wpath, wfile), wnVarName);
                    wnVec = sW.(wnVarName)(:);
                    wnDim = numel(wnVec);
                end
            end
        end
    end

    % ---------------- Step 3: If no wnDim yet, ask for dimension ----------------
    if isempty(wnDim)
        dimIn = inputdlg( ...
            'Enter wavenumber dimension (e.g. 805 for 805 x 20000):', ...
            'Wavenumber dimension', 1, {'805'});
        if isempty(dimIn)
            return;
        end
        wnDim = str2double(dimIn{1});
        if isnan(wnDim) || wnDim <= 0
            errordlg('Invalid wavenumber dimension.', 'Input error');
            return;
        end
        wnVec = [];
    end

    % ---------------- Step 4: Build GUI layout ----------------
    f = figure('Name', 'Raman Cosmic-Ray Inspector', ...
               'NumberTitle', 'off', ...
               'Units', 'normalized', ...
               'Position', [0.05, 0.05, 0.9, 0.9]);

    % Top toolbar panel (fixed at top)
    topPanel = uipanel('Parent', f, ...
                       'Units', 'normalized', ...
                       'Position', [0, 0.90, 1, 0.10], ...
                       'Title', 'Controls');

    uicontrol('Parent', topPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.01, 0.25, 0.07, 0.5], ...
              'String', 'Variable:', ...
              'HorizontalAlignment', 'left');

    varPopup = uicontrol('Parent', topPanel, 'Style', 'popupmenu', ...
                         'Units', 'normalized', ...
                         'Position', [0.08, 0.25, 0.18, 0.5], ...
                         'String', dataVarNames, ...
                         'Callback', @onVariableSelected);

    uicontrol('Parent', topPanel, 'Style', 'pushbutton', ...
              'Units', 'normalized', ...
              'Position', [0.27, 0.25, 0.08, 0.5], ...
              'String', 'Previous', ...
              'Callback', @onPreviousVar);

    uicontrol('Parent', topPanel, 'Style', 'pushbutton', ...
              'Units', 'normalized', ...
              'Position', [0.36, 0.25, 0.08, 0.5], ...
              'String', 'Next', ...
              'Callback', @onNextVar);

    uicontrol('Parent', topPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.46, 0.55, 0.20, 0.35], ...
              'String', 'Threshold (curvature score):', ...
              'HorizontalAlignment', 'left');

    thrSlider = uicontrol('Parent', topPanel, 'Style', 'slider', ...
                          'Units', 'normalized', ...
                          'Min', 5, 'Max', 150, 'Value', threshold, ...
                          'Position', [0.46, 0.20, 0.20, 0.30], ...
                          'Callback', @onThresholdChanged);

    thrValueLabel = uicontrol('Parent', topPanel, 'Style', 'text', ...
                              'Units', 'normalized', ...
                              'Position', [0.67, 0.20, 0.08, 0.30], ...
                              'String', sprintf('Value: %.1f', threshold), ...
                              'HorizontalAlignment', 'left');

    statsBox = uicontrol('Parent', topPanel, 'Style', 'edit', ...
                         'Units', 'normalized', ...
                         'Position', [0.76, 0.05, 0.23, 0.85], ...
                         'HorizontalAlignment', 'left', ...
                         'Max', 2, 'Min', 0, ...
                         'Enable', 'inactive', ...
                         'String', '');

    % Top axes: original spectra
    axMain = axes('Parent', f, ...
                  'Units', 'normalized', ...
                  'Position', [0.08, 0.52, 0.88, 0.35]);
    title(axMain, 'Original spectra (click to mark/unmark)');
    xlabel(axMain, 'Wavenumber');
    ylabel(axMain, 'Intensity');
    enableDefaultInteractivity(axMain);

    % Middle panel: start/end + Delete MARKED
    midPanel = uipanel('Parent', f, ...
                       'Units', 'normalized', ...
                       'Position', [0, 0.43, 1, 0.07]);

    uicontrol('Parent', midPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.08, 0.15, 0.10, 0.7], ...
              'String', 'Start spectrum:', ...
              'HorizontalAlignment', 'left');

    startEdit = uicontrol('Parent', midPanel, 'Style', 'edit', ...
                          'Units', 'normalized', ...
                          'Position', [0.19, 0.25, 0.05, 0.5], ...
                          'String', '1', ...
                          'Callback', @onStartChanged);

    uicontrol('Parent', midPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.27, 0.15, 0.10, 0.7], ...
              'String', 'End spectrum:', ...
              'HorizontalAlignment', 'left');

    endEdit = uicontrol('Parent', midPanel, 'Style', 'edit', ...
                        'Units', 'normalized', ...
                        'Position', [0.38, 0.25, 0.05, 0.5], ...
                        'String', '1', ...
                        'Callback', @onEndChanged);

    uicontrol('Parent', midPanel, 'Style', 'pushbutton', ...
              'Units', 'normalized', ...
              'Position', [0.48, 0.20, 0.15, 0.6], ...
              'String', 'Delete MARKED', ...
              'Callback', @onDeleteMarked);

    % Bottom axes: cosmic candidates
    axCosmic = axes('Parent', f, ...
                    'Units', 'normalized', ...
                    'Position', [0.08, 0.20, 0.88, 0.25]);
    title(axCosmic, 'Cosmic candidates (auto-detected, stacked)');
    xlabel(axCosmic, 'Wavenumber');
    ylabel(axCosmic, 'Intensity');
    enableDefaultInteractivity(axCosmic);

    % Cosmic range panel (for bottom axes)
    cosPanel = uipanel('Parent', f, ...
                       'Units', 'normalized', ...
                       'Position', [0, 0.13, 1, 0.07]);

    uicontrol('Parent', cosPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.08, 0.15, 0.12, 0.7], ...
              'String', 'Cosmic start:', ...
              'HorizontalAlignment', 'left');

    cosStartEdit = uicontrol('Parent', cosPanel, 'Style', 'edit', ...
                             'Units', 'normalized', ...
                             'Position', [0.20, 0.25, 0.05, 0.5], ...
                             'String', '1', ...
                             'Callback', @onCosStartChanged);

    uicontrol('Parent', cosPanel, 'Style', 'text', ...
              'Units', 'normalized', ...
              'Position', [0.30, 0.15, 0.12, 0.7], ...
              'String', 'Cosmic end:', ...
              'HorizontalAlignment', 'left');

    cosEndEdit = uicontrol('Parent', cosPanel, 'Style', 'edit', ...
                           'Units', 'normalized', ...
                           'Position', [0.42, 0.25, 0.05, 0.5], ...
                           'String', '1', ...
                           'Callback', @onCosEndChanged);

    % Bottom bar: play, show stacked, delete cosmic, speed
    bottomPanel = uipanel('Parent', f, ...
                          'Units', 'normalized', ...
                          'Position', [0, 0.05, 1, 0.08]);

    playPauseBtn = uicontrol('Parent', bottomPanel, 'Style', 'pushbutton', ...
                             'Units', 'normalized', ...
                             'Position', [0.05, 0.20, 0.16, 0.6], ...
                             'String', 'Play', ...
                             'Callback', @onPlayPause);

    uicontrol('Parent', bottomPanel, 'Style', 'pushbutton', ...
              'Units', 'normalized', ...
              'Position', [0.24, 0.20, 0.18, 0.6], ...
              'String', 'Show stacked cosmic view', ...
              'Callback', @(~,~) plotCosmicStack());

    uicontrol('Parent', bottomPanel, 'Style', 'pushbutton', ...
              'Units', 'normalized', ...
              'Position', [0.45, 0.20, 0.18, 0.6], ...
              'String', 'Delete COSMIC candidates', ...
              'Callback', @onDeleteCosmic);

    speedLabel = uicontrol('Parent', bottomPanel, 'Style', 'text', ...
                           'Units', 'normalized', ...
                           'Position', [0.66, 0.45, 0.30, 0.45], ...
                           'String', sprintf('Movie speed (s/frame): %.3f', movieDelaySec), ...
                           'HorizontalAlignment', 'left');

    speedSlider = uicontrol('Parent', bottomPanel, 'Style', 'slider', ...
                            'Units', 'normalized', ...
                            'Min', 0.005, 'Max', 0.3, 'Value', movieDelaySec, ...
                            'Position', [0.66, 0.10, 0.30, 0.35], ...
                            'Callback', @onSpeedChanged);

    % Initialize first variable
    onVariableSelected(varPopup, []);

    % ---------------- Nested functions ----------------

    function onVariableSelected(src, ~)
        idx = src.Value;
        if idx < 1 || idx > numel(dataVarNames)
            return;
        end
        currentIndex     = idx;
        selectedVariable = dataVarNames{idx};

        raw = evalin('base', selectedVariable);
        [r, c] = size(raw);
        currentWasTransposed = false;

        if c == wnDim
            currentSpectra = raw;
        elseif r == wnDim
            currentSpectra = raw.';
            currentWasTransposed = true;
        else
            errordlg(sprintf('Variable "%s" does not have dimension %d in rows or columns.', ...
                             selectedVariable, wnDim), ...
                     'Dimension mismatch');
            currentSpectra   = [];
            nSpectra         = 0;
            manualMask       = [];
            autoCosmicMask   = [];
            cosmicScore      = [];
            cla(axMain, 'reset');
            cla(axCosmic, 'reset');
            return;
        end

        [nSpectra, ~] = size(currentSpectra);
        startSpectrum = 1;
        endSpectrum   = nSpectra;

        if ~isempty(wnVec) && numel(wnVec) == wnDim
            xAxis = wnVec(:).';
        else
            xAxis = 1:wnDim;
        end

        manualMask = false(1, nSpectra); % reset manual marks
        computeCosmicScores();
        updateEditFields();
        plotSpectra();
    end

    function computeCosmicScores()
        % Combination detector:
        %   1) curvatureScore = max |second difference of residuals| / sigmaRow
        %   2) width/shape filter: require at least one very narrow, isolated spike
        %   Final mask = (curvatureScore > threshold) AND hasNarrowSpike

        if isempty(currentSpectra)
            return;
        end

        window = 7;  % median window for baseline
        bg = movmedian(currentSpectra, window, 2);
        resid = currentSpectra - bg;                 % [nSpec x wnDim]

        medRow   = median(resid, 2);
        absDev   = abs(resid - medRow);
        sigmaRow = 1.4826 * median(absDev, 2);       % nSpec x 1
        sigmaRow(sigmaRow <= 0 | isnan(sigmaRow)) = 1;

        % ---- curvature score ----
        dd = resid(:, 3:end) - 2*resid(:, 2:end-1) + resid(:, 1:end-2); % nSpec x (wnDim-2)
        scoreMatrix = abs(dd) ./ sigmaRow;
        curvatureScore = max(scoreMatrix, [], 2);

        % ---- shape / width filter ----
        R = resid ./ sigmaRow;                       % normalized residuals (sigmas)
        [nSpec, nPts] = size(R);
        hasNarrowSpike = false(nSpec, 1);

        maxWidthPts          = 3;     % max width (points) at half-height
        baseAmpThreshSigma   = 6;     % peak > 6 sigma
        neighbourRatioThresh = 2.5;   % central point at least 2.5× neighbours

        for s = 1:nSpec
            r = R(s, :);
            r(1:2)      = 0;
            r(end-1:end) = 0;

            isMax = (r > 0) & (r > circshift(r, 1)) & (r >= circshift(r, -1));
            candIdx = find(isMax & r > baseAmpThreshSigma);

            for k = 1:numel(candIdx)
                i = candIdx(k);
                peakAmp = r(i);

                neigh = [r(i-2:i-1), r(i+1:i+2)];
                neighMax = max(neigh);
                if neighMax <= 0
                    neighMax = 1e-6;
                end
                ratio = peakAmp / neighMax;
                if ratio < neighbourRatioThresh
                    continue;
                end

                half = peakAmp * 0.5;
                left = i;
                while left > 1 && r(left-1) > half
                    left = left - 1;
                end
                right = i;
                while right < nPts && r(right+1) > half
                    right = right + 1;
                end
                widthPts = right - left + 1;

                if widthPts <= maxWidthPts
                    hasNarrowSpike(s) = true;
                    break;
                end
            end
        end

        cosmicScore    = curvatureScore;
        autoCosmicMask = (cosmicScore > threshold) & hasNarrowSpike;

        % reset cosmic index range
        nCos = nnz(autoCosmicMask);
        cosStart = 1;
        cosEnd   = max(1, nCos);
        updateCosRangeFields();

        updateStatsText();
        plotCosmicStack();
    end

    function updateStatsText()
        if isempty(cosmicScore) || nSpectra == 0
            set(statsBox, 'String', '');
            return;
        end

        nCos    = sum(autoCosmicMask);
        fracCos = 100 * nCos / nSpectra;
        nManual = sum(manualMask);

        medAll = median(cosmicScore);
        medCos = NaN;
        if nCos > 0
            medCos = median(cosmicScore(autoCosmicMask));
        end

        txt = sprintf(['Variable: %s\n', ...
                       'Total spectra: %d\n', ...
                       'Auto cosmic candidates: %d (%.3f%%)\n', ...
                       'Manual marked (any view): %d\n', ...
                       'Threshold (curvature): %.1f\n', ...
                       'Median score (cosmic/all): %.1f / %.1f\n', ...
                       'Shape filter: width <= 3 pts, >6σ & ratio >= 2.5'], ...
                      selectedVariable, nSpectra, nCos, fracCos, ...
                      nManual, threshold, medCos, medAll);
        set(statsBox, 'String', txt);
    end

    function updateEditFields()
        set(startEdit, 'String', num2str(startSpectrum));
        set(endEdit,   'String', num2str(endSpectrum));
    end

    function updateCosRangeFields()
        if ~ishandle(cosStartEdit) || ~ishandle(cosEndEdit)
            return;
        end
        idxCos = find(autoCosmicMask);
        nCos = numel(idxCos);
        if nCos == 0
            cosStart = 1;
            cosEnd   = 1;
        else
            cosStart = max(1, min(cosStart, nCos));
            cosEnd   = max(cosStart, min(cosEnd, nCos));
        end
        set(cosStartEdit, 'String', num2str(cosStart));
        set(cosEndEdit,   'String', num2str(cosEnd));
    end

    function plotSpectra()
        if isempty(currentSpectra) || nSpectra == 0
            cla(axMain, 'reset');
            cla(axCosmic, 'reset');
            return;
        end

        startSpectrum = max(1, min(startSpectrum, nSpectra));
        endSpectrum   = max(startSpectrum, min(endSpectrum, nSpectra));
        updateEditFields();

        idx = startSpectrum:endSpectrum;

        if numel(idx) > MAX_PLOTTED_SPECTRA
            step = ceil(numel(idx) / MAX_PLOTTED_SPECTRA);
            idxPlot = idx(1:step:end);
            extraInfo = sprintf(' (showing %d of %d in range)', ...
                                numel(idxPlot), numel(idx));
        else
            idxPlot = idx;
            extraInfo = '';
        end

        cla(axMain, 'reset');
        hold(axMain, 'on');

        idxManual   = idxPlot(manualMask(idxPlot));
        idxNormal   = idxPlot(~manualMask(idxPlot));

        if ~isempty(idxNormal)
            Y = currentSpectra(idxNormal, :).';
            h = plot(axMain, xAxis, Y);
            set(h, {'UserData'}, num2cell(idxNormal(:)));
            set(h, 'ButtonDownFcn', @onSpectrumClicked);
        end

        if ~isempty(idxManual)
            Y = currentSpectra(idxManual, :).';
            h = plot(axMain, xAxis, Y, 'r-');
            set(h, {'UserData'}, num2cell(idxManual(:)));
            set(h, 'ButtonDownFcn', @onSpectrumClicked);
        end

        hold(axMain, 'off');
        xlabel(axMain, 'Wavenumber');
        ylabel(axMain, 'Intensity');
        title(axMain, sprintf('Spectra %d–%d — %s%s', ...
              startSpectrum, endSpectrum, selectedVariable, extraInfo), ...
              'Interpreter', 'none');
        enableDefaultInteractivity(axMain);

        plotCosmicStack();
    end

    function plotCosmicStack()
        if ~ishandle(axCosmic)
            return;
        end
        cla(axCosmic, 'reset');
        idxCos = find(autoCosmicMask);
        nCos = numel(idxCos);
        if nCos == 0
            title(axCosmic, 'Cosmic candidates (none at current threshold)');
            xlabel(axCosmic, 'Wavenumber');
            ylabel(axCosmic, 'Intensity');
            enableDefaultInteractivity(axCosmic);
            return;
        end

        % apply cosmic index range
        cosStartLocal = max(1, min(cosStart, nCos));
        cosEndLocal   = max(cosStartLocal, min(cosEnd, nCos));
        cosStart = cosStartLocal;
        cosEnd   = cosEndLocal;
        updateCosRangeFields();

        idxCosRange = idxCos(cosStart:cosEnd);

        % sub-sample if too many
        if numel(idxCosRange) > MAX_PLOTTED_SPECTRA
            step = ceil(numel(idxCosRange) / MAX_PLOTTED_SPECTRA);
            idxCosRange = idxCosRange(1:step:end);
        end

        hold(axCosmic, 'on');
        for k = 1:numel(idxCosRange)
            i = idxCosRange(k);
            y = currentSpectra(i, :);
            if manualMask(i)
                col = [0.5 0.5 0.5]; % manually marked -> grey
            else
                col = [1 0 0];       % auto-only -> red
            end
            h = plot(axCosmic, xAxis, y, 'Color', col);
            set(h, 'UserData', i);
            set(h, 'ButtonDownFcn', @onCosmicClicked); % left/right handled there
        end
        hold(axCosmic, 'off');

        xlabel(axCosmic, 'Wavenumber');
        ylabel(axCosmic, 'Intensity');
        title(axCosmic, sprintf('Cosmic candidates (showing %d of %d)', ...
              numel(idxCosRange), nCos));
        enableDefaultInteractivity(axCosmic);
    end

    function onSpectrumClicked(src, ~)
        idx = src.UserData;
        if isempty(idx) || idx < 1 || idx > nSpectra
            return;
        end
        manualMask(idx) = ~manualMask(idx);
        updateStatsText();
        plotSpectra();
    end

    function onCosmicClicked(src, ~)
        idx = src.UserData;
        if isempty(idx) || idx < 1 || idx > nSpectra
            return;
        end

        selType = get(f, 'SelectionType');
        if strcmp(selType, 'alt')
            % right-click -> inspect single spectrum in new figure
            figure('Name', sprintf('Cosmic candidate #%d (score %.2f)', ...
                                   idx, cosmicScore(idx)), ...
                   'NumberTitle', 'off');
            plot(xAxis, currentSpectra(idx, :), 'r-');
            xlabel('Wavenumber');
            ylabel('Intensity');
            title(sprintf('Cosmic candidate index %d, score %.2f', ...
                  idx, cosmicScore(idx)));
        else
            % left-click -> toggle manual mark (grey in bottom, red in top)
            manualMask(idx) = ~manualMask(idx);
            updateStatsText();
            plotSpectra();
        end
    end

    function onThresholdChanged(src, ~)
        threshold = src.Value;
        threshold = round(threshold * 10) / 10;
        set(src, 'Value', threshold);
        set(thrValueLabel, 'String', sprintf('Value: %.1f', threshold));

        if isempty(cosmicScore)
            return;
        end
        computeCosmicScores();
        plotSpectra();
    end

    function onSpeedChanged(src, ~)
        movieDelaySec = src.Value;
        movieDelaySec = max(0.001, movieDelaySec);
        set(speedLabel, 'String', ...
            sprintf('Movie speed (s/frame): %.3f', movieDelaySec));
    end

    function onStartChanged(~, ~)
        if nSpectra == 0, return; end
        v = str2double(get(startEdit, 'String'));
        if isnan(v), v = startSpectrum; end
        v = round(v);
        v = max(1, min(v, nSpectra));
        startSpectrum = v;
        if endSpectrum < startSpectrum
            endSpectrum = startSpectrum;
        end
        updateEditFields();
        plotSpectra();
    end

    function onEndChanged(~, ~)
        if nSpectra == 0, return; end
        v = str2double(get(endEdit, 'String'));
        if isnan(v), v = endSpectrum; end
        v = round(v);
        v = max(1, min(v, nSpectra));
        endSpectrum = max(startSpectrum, v);
        updateEditFields();
        plotSpectra();
    end

    function onCosStartChanged(~, ~)
        idxCos = find(autoCosmicMask);
        nCos = numel(idxCos);
        if nCos == 0, return; end
        v = str2double(get(cosStartEdit, 'String'));
        if isnan(v), v = cosStart; end
        v = round(v);
        v = max(1, min(v, nCos));
        cosStart = v;
        if cosEnd < cosStart
            cosEnd = cosStart;
        end
        updateCosRangeFields();
        plotCosmicStack();
    end

    function onCosEndChanged(~, ~)
        idxCos = find(autoCosmicMask);
        nCos = numel(idxCos);
        if nCos == 0, return; end
        v = str2double(get(cosEndEdit, 'String'));
        if isnan(v), v = cosEnd; end
        v = round(v);
        v = max(1, min(v, nCos));
        cosEnd = max(cosStart, v);
        updateCosRangeFields();
        plotCosmicStack();
    end

    function onDeleteMarked(~, ~)
        if isempty(currentSpectra) || nSpectra == 0
            return;
        end
        if ~any(manualMask)
            msgbox('No spectra are manually marked.', ...
                   'Delete MARKED', 'warn');
            return;
        end

        nDel = sum(manualMask);
        answ = questdlg( ...
            sprintf('Delete %d manually marked spectra from "%s" (workspace only)?', ...
                    nDel, selectedVariable), ...
            'Confirm deletion', 'Yes', 'No', 'No');
        if ~strcmp(answ, 'Yes')
            return;
        end

        keepMask = ~manualMask;
        currentSpectra = currentSpectra(keepMask, :);
        cosmicScore    = cosmicScore(keepMask);
        autoCosmicMask = autoCosmicMask(keepMask);
        manualMask     = false(1, sum(keepMask));
        [nSpectra, ~]  = size(currentSpectra);

        startSpectrum = 1;
        endSpectrum   = nSpectra;

        computeCosmicScores();
        plotSpectra();
        writeBackToWorkspace();
    end

    function onDeleteCosmic(~, ~)
        if isempty(currentSpectra) || nSpectra == 0
            return;
        end
        if ~any(autoCosmicMask)
            msgbox('No auto-detected cosmic candidates at current threshold.', ...
                   'Delete COSMIC', 'warn');
            return;
        end

        nDel = sum(autoCosmicMask);
        answ = questdlg( ...
            sprintf('Delete %d auto-detected cosmic candidates from "%s"?', ...
                    nDel, selectedVariable), ...
            'Confirm deletion', 'Yes', 'No', 'No');
        if ~strcmp(answ, 'Yes')
            return;
        end

        keepMask = ~autoCosmicMask;
        currentSpectra = currentSpectra(keepMask, :);
        cosmicScore    = cosmicScore(keepMask);
        manualMask     = manualMask(keepMask);
        [nSpectra, ~]  = size(currentSpectra);

        startSpectrum = 1;
        endSpectrum   = nSpectra;

        computeCosmicScores();
        plotSpectra();
        writeBackToWorkspace();
    end

    function writeBackToWorkspace()
        out = currentSpectra;
        if currentWasTransposed
            out = out.';
        end
        assignin('base', selectedVariable, out);
    end

    function onPlayPause(~, ~)
        if isempty(currentSpectra) || nSpectra == 0
            return;
        end

        idxCos = find(autoCosmicMask);
        if isempty(idxCos)
            msgbox('No cosmic candidates to play.', 'Cosmic movie', 'warn');
            return;
        end

        if isPlaying
            isPlaying = false;
            set(playPauseBtn, 'String', 'Play');
            return;
        end

        isPlaying = true;
        set(playPauseBtn, 'String', 'Pause');

        for k = 1:numel(idxCos)
            if ~ishandle(f) || ~ishandle(axCosmic)
                isPlaying = false;
                break;
            end
            if ~isPlaying
                break;  % paused: keep last frame
            end
            i = idxCos(k);
            cla(axCosmic, 'reset');
            h = plot(axCosmic, xAxis, currentSpectra(i, :), 'r-');
            set(h, 'UserData', i);
            set(h, 'ButtonDownFcn', @onCosmicClicked);
            xlabel(axCosmic, 'Wavenumber');
            ylabel(axCosmic, 'Intensity');
            title(axCosmic, sprintf('Cosmic candidate %d of %d (index %d)', ...
                  k, numel(idxCos), i));
            enableDefaultInteractivity(axCosmic);
            drawnow;
            pause(movieDelaySec);
        end

        if isPlaying
            isPlaying = false;
            set(playPauseBtn, 'String', 'Play');
            plotCosmicStack();
        end
    end

    function onPreviousVar(~, ~)
        if currentIndex > 1
            currentIndex = currentIndex - 1;
            set(varPopup, 'Value', currentIndex);
            onVariableSelected(varPopup, []);
        end
    end

    function onNextVar(~, ~)
        if currentIndex < numel(dataVarNames)
            currentIndex = currentIndex + 1;
            set(varPopup, 'Value', currentIndex);
            onVariableSelected(varPopup, []);
        end
    end
end

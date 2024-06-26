function OutlierStrip()
    % Global variable declarations to ensure scope visibility throughout the function
    global selectedVariable markedForDeletion currentIndex cleanedVariables wavenumberDimension startSpectrum endSpectrum;

    % Initialize global variables
    selectedVariable = '';
    markedForDeletion = [];
    currentIndex = 1; % This will be set properly after loading variables
    cleanedVariables = {}; % This will be filled with variable names matching the pattern
    wavenumberDimension = 0; % This will be set based on user input
    startSpectrum = 1; % Start index for spectra
    endSpectrum = 0; % End index for spectra

    % GUI component positions
    dropdownPos = [140, 50, 200, 20];
    deleteButtonPos = [360, 50, 180, 20];
    startLabelPos = [580, 85, 50, 20];
    startEditPos = [630, 85, 50, 20];
    endLabelPos = [580, 50, 50, 20];
    endEditPos = [630, 50, 50, 20];
    deleteRangeButtonPos = [720, 85, 180, 20];
    prevButtonPos = [720, 50, 90, 20];
    nextButtonPos = [820, 50, 90, 20];

    % Ask the user whether they want to enter prefixes, suffixes, or both
    choice = questdlg('Filter variables by:', ...
                      'Variable Filtering', ...
                      'Prefixes', 'Suffixes', 'Both', ...
                      'Both');

    % Exit the function if the user cancels or closes the dialog box
    if isempty(choice)
        return;
    end

    prefixes = {};
    suffixes = {};

    % Depending on the user's choice, prompt for prefixes, suffixes, or both
    switch choice
        case 'Prefixes'
            prefixInput = inputdlg('Enter prefixes (comma-separated):', 'Prefixes', [1 50]);
            if ~isempty(prefixInput)
                prefixes = strsplit(prefixInput{1}, ',');
            end
        case 'Suffixes'
            suffixInput = inputdlg('Enter suffixes (comma-separated):', 'Suffixes', [1 50]);
            if ~isempty(suffixInput)
                suffixes = strsplit(suffixInput{1}, ',');
            end
        case 'Both'
            bothInput = inputdlg({'Enter prefixes (comma-separated):', 'Enter suffixes (comma-separated):'}, ...
                                  'Prefixes and Suffixes', [1 50]);
            if ~isempty(bothInput)
                prefixes = strsplit(bothInput{1}, ',');
                suffixes = strsplit(bothInput{2}, ',');
            end
    end

    % Prompt for the wavenumber dimension directly after fetching prefixes/suffixes
    dimensionInput = inputdlg('Enter the expected dimension for wavenumbers (e.g., 660):', ...
                              'Wavenumber Dimension', [1 50]);
    if isempty(dimensionInput)
        msgbox('Wavenumber dimension input is required.', 'Input Error', 'error');
        return;
    end
    wavenumberDimension = str2double(dimensionInput{1});
    if isnan(wavenumberDimension)
        msgbox('Invalid wavenumber dimension entered.', 'Input Error', 'error');
        return;
    end

    % Construct the regex pattern
    pattern = buildPattern(prefixes, suffixes);

    % Fetch variables matching the pattern
    cleanedVariables = evalin('base', sprintf("who('-regexp', '%s')", pattern));

    % Proceed with GUI initialization only if there are variables to show
    if isempty(cleanedVariables)
        msgbox('No variables match your criteria.', 'Variable Filtering', 'warn');
        return;
    end

    % Adjusted UI components for clarity
    f = figure('Name', 'Interactive Spectra Viewer', 'NumberTitle', 'off', 'Position', [100, 100, 1000, 600]);
    ax = axes('Parent', f, 'Position', [0.1 0.3 0.8 0.6]);
    title(ax, 'Select a variable');

    % Dropdown menu for variable selection
    variableDropdown = uicontrol('Style', 'popupmenu', 'String', cleanedVariables, 'Position', dropdownPos, 'Callback', @onVariableSelected);

    % Button for deleting marked spectra
    deleteButton = uicontrol('Style', 'pushbutton', 'String', 'Delete Marked Spectra', 'Position', deleteButtonPos, 'Callback', @onDeleteConfirmed);

    % Labels and Edit fields for specifying the range
    uicontrol('Style', 'text', 'String', 'Start:', 'Position', startLabelPos);
    startEdit = uicontrol('Style', 'edit', 'String', num2str(startSpectrum), 'Position', startEditPos, 'Callback', @onStartChanged);
    uicontrol('Style', 'text', 'String', 'End:', 'Position', endLabelPos);
    endEdit = uicontrol('Style', 'edit', 'String', num2str(endSpectrum), 'Position', endEditPos, 'Callback', @onEndChanged);

    % Button to delete a range of spectra
    deleteRangeButton = uicontrol('Style', 'pushbutton', 'String', 'Delete Range', 'Position', deleteRangeButtonPos, 'Callback', @onDeleteRange);

    % Next and Previous buttons for easy toggling
    prevButton = uicontrol('Style', 'pushbutton', 'String', 'Previous', 'Position', prevButtonPos, 'Callback', @onPrevious);
    nextButton = uicontrol('Style', 'pushbutton', 'String', 'Next', 'Position', nextButtonPos, 'Callback', @onNext);

    % Ensure we handle the case where cleanedVariables might be empty or the initial selection is invalid
    if ~isempty(cleanedVariables)
        currentIndex = min(currentIndex, length(cleanedVariables)); % Ensure valid index
        onVariableSelected(variableDropdown, []); % Manually trigger selection update
    end

    % Helper function to construct the regex pattern
    function pattern = buildPattern(prefixes, suffixes)
        prefixPattern = strjoin(string(prefixes), '|');
        suffixPattern = strjoin(string(suffixes), '|');

        if isempty(prefixes) && ~isempty(suffixes)
            pattern = ".*(" + suffixPattern + ")$";
        elseif ~isempty(prefixes) && isempty(suffixes)
            pattern = "^(" + prefixPattern + ").*";
        else
            pattern = "^(" + prefixPattern + ").*(" + suffixPattern + ")$";
        end
    end

    % Callback function for variable selection
    function onVariableSelected(src, ~)
    if isempty(cleanedVariables)
        return; % Guard against callback without selection
    end
    selectedVariable = cleanedVariables{src.Value};
    markedForDeletion = []; % Reset marked indices
    startSpectrum = 1; % Reset start spectrum when variable changes
    spectraSize = size(evalin('base', selectedVariable));
    
    % Check if we need to transpose the spectra to match the user-defined wavenumber dimension
    if spectraSize(2) == wavenumberDimension
        endSpectrum = spectraSize(1);
    else
        endSpectrum = spectraSize(2);
    end
    
    updateStartEndEditFields();
    plotSpectra(); % Plot spectra for selected variable
    end

    % Callback for Next button
    function onNext(~, ~)
        if currentIndex < length(cleanedVariables)
            currentIndex = currentIndex + 1;
            updateVariableSelection();
        end
    end

    % Callback for Previous button
    function onPrevious(~, ~)
        if currentIndex > 1
            currentIndex = currentIndex - 1;
            updateVariableSelection();
        end
    end

    % Update the variable selection based on currentIndex
    function updateVariableSelection()
        if isempty(cleanedVariables)
            return; % Guard against empty selection
        end
        selectedVariable = cleanedVariables{currentIndex};
        variableDropdown.Value = currentIndex; % Update dropdown selection
        markedForDeletion = []; % Reset marked indices
        startSpectrum = 1; % Reset start spectrum when variable changes
        endSpectrum = size(evalin('base', selectedVariable), 1); % Set end spectrum to total spectra count for the selected variable
        updateStartEndEditFields();
        plotSpectra(); % Plot spectra for selected variable
    end

    % Function to update start index when the edit field changes
    function onStartChanged(~, ~)
        startStr = startEdit.String;
        startVal = str2double(startStr);
        if ~isnan(startVal) && startVal > 0 && startVal <= endSpectrum
            startSpectrum = startVal;
            plotSpectra();
        else
            startEdit.String = num2str(startSpectrum);
        end
    end

    % Function to update end index when the edit field changes
    function onEndChanged(~, ~)
        endStr = endEdit.String;
        endVal = str2double(endStr);
        if ~isnan(endVal) && endVal >= startSpectrum && endVal <= size(evalin('base', selectedVariable), 1)
            endSpectrum = endVal;
            plotSpectra();
        else
            endEdit.String = num2str(endSpectrum);
        end
    end

    % Update the start and end edit fields with current values
    function updateStartEndEditFields()
        startEdit.String = num2str(startSpectrum);
        endEdit.String = num2str(endSpectrum);
    end

    % Function to plot selected range of spectra for a variable
    function plotSpectra()
        cla(ax); % Clear previous plots
        spectra = evalin('base', selectedVariable); % Load selected variable data
        % Transpose data if needed based on the user input for the wavenumber dimension
        if size(spectra, 2) ~= wavenumberDimension
            spectra = spectra.';
        end

        % Plot the selected range of spectra
        hold(ax, 'on');
        for i = startSpectrum:endSpectrum
            p = plot(ax, spectra(i, :), 'Tag', num2str(i)); % Tag each line with its index
            p.ButtonDownFcn = @markSpectrum; % Set callback for marking spectrum
        end
        hold(ax, 'off');
        xlabel(ax, 'Wavenumber');
        ylabel(ax, 'Intensity');
        title(ax, ['Spectra ', num2str(startSpectrum), ' to ', num2str(endSpectrum), ' - ', selectedVariable], 'Interpreter', 'none');
    end

    % Callback to mark spectrum for deletion
    function markSpectrum(src, ~)
        idx = str2double(src.Tag); % Retrieve index from tag
        if ismember(idx, markedForDeletion)
            % If already marked, unmark and reset color
            src.Color = [0, 0, 1];
            markedForDeletion(markedForDeletion == idx) = [];
        else
            % Mark for deletion and change color
            src.Color = [1, 0, 0];
            markedForDeletion = [markedForDeletion, idx];
        end
    end

    % Confirm deletion of marked spectra
    function onDeleteConfirmed(~, ~)
        if ~isempty(markedForDeletion) && ~isempty(selectedVariable)
            % Load the spectra data from the base workspace
            spectra = evalin('base', selectedVariable);

            % Check if we need to transpose the spectra to match the user-defined wavenumber dimension
            if size(spectra, 2) == wavenumberDimension
                % If the number of columns matches the wavenumber dimension, the data is correctly oriented
                % Delete the marked spectra (assuming they are rows)
                spectra(markedForDeletion, :) = [];
            else
                % If not, the spectra are stored in columns, so we delete the marked columns
                spectra(:, markedForDeletion) = [];
            end

            % Update the variable in the base workspace with the modified spectra
            assignin('base', selectedVariable, spectra);

            % Clear marked indices and replot
            markedForDeletion = [];
            plotSpectra();
        end
    end

    % Callback to delete a range of spectra
    function onDeleteRange(~, ~)
        if ~isempty(selectedVariable)
            % Load the spectra data from the base workspace
            spectra = evalin('base', selectedVariable);
          
            % Check if we need to transpose the spectra to match the user-defined wavenumber dimension
            if size(spectra, 2) == wavenumberDimension
                % If the number of columns matches the wavenumber dimension, the data is correctly oriented
                            % Delete the range of spectra
                spectra(startSpectrum:endSpectrum, :) = [];
            else
                % If not, the spectra are stored in columns, so we delete the marked columns
                            % Delete the range of spectra
                spectra(:, startSpectrum:endSpectrum) = [];
            end
            % Update the variable in the base workspace with the modified spectra
            assignin('base', selectedVariable, spectra);

            % Clear marked indices and replot
            markedForDeletion = [];
            plotSpectra();
        end
    end
end

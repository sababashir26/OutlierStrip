function OutlierStrip()
    % Ask the user whether they want to enter prefixes, suffixes, or both
    choice = questdlg('Filter variables by:', ...
                      'Variable Filtering', ...
                      'Prefixes', 'Suffixes', 'Both', ...
                      'Both'); % Corrected for clarity and to avoid the warning
    
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
    
     % Initialize GUI components
    f = figure('Name', 'Interactive Spectra Viewer', 'NumberTitle', 'off', 'Position', [100, 100, 800, 600]);
    ax = axes('Parent', f, 'Position', [0.1 0.3 0.8 0.6]);
    title(ax, 'Select a variable');
    % Drop-down menu for variable selection
    variableDropdown = uicontrol('Style', 'popupmenu', 'String', cleanedVariables, 'Position', [20, 50, 200, 20], 'Callback', @onVariableSelected);

    % Button for deleting marked spectra
    deleteButton = uicontrol('Style', 'pushbutton', 'String', 'Delete Marked Spectra', 'Position', [240, 50, 180, 20], 'Callback', @onDeleteConfirmed);
    
    % Global variables for state tracking
    global selectedVariable markedForDeletion;
    selectedVariable = '';
    markedForDeletion = [];

    % Callback function for variable selection
    function onVariableSelected(src, ~)
        selectedVariable = cleanedVariables{src.Value};
        markedForDeletion = []; % Reset marked indices
        plotSpectra(); % Plot spectra for selected variable
        
    end

    % Function to plot all spectra for selected variable
    function plotSpectra()
        cla(ax); % Clear previous plots
        spectra = evalin('base', selectedVariable); % Load selected variable data
        % Transpose data if needed based on the user input for the wavenumber dimension
        if size(spectra, 2) ~= wavenumberDimension
            spectra = spectra.';
        end

        hold(ax, 'on'); % Hold on for multiple plots
        for i = 1:size(spectra, 1)
            p = plot(ax, spectra(i, :), 'Tag', num2str(i)); % Tag each line with its index
            p.ButtonDownFcn = @markSpectrum; % Set callback for marking spectrum
        end
        hold(ax, 'off');
        xlabel(ax, 'Wavenumber');
        ylabel(ax, 'Intensity');
        title(ax, ['All Spectra - ' selectedVariable], 'Interpreter', 'none');
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
            % Remove marked spectra from data
            spectra = evalin('base', selectedVariable);
            spectra(:,markedForDeletion) = [];
            % Update variable in base workspace
            assignin('base', selectedVariable, spectra);
            % Clear marked indices and replot
            markedForDeletion = [];
            plotSpectra();
        end
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
end


    
    

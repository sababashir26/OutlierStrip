# OutlierStrip
OutlierStrip is a MATLAB tool designed to empower researchers and data analysts working with spectral data to efficiently identify and remove outliers. By offering an interactive graphical user interface (GUI), OutlierStrip simplifies the process of refining spectral datasets, ensuring cleaner data for further analysis or modeling tasks.

### Core Features:

- Custom Variable Filtering: Upon launching OutlierStrip, you'll be asked whether you want to filter variables by prefixes, suffixes, or both. This step is crucial for narrowing down the list of variables (spectral datasets) you wish to analyze, especially in environments with numerous datasets.
   - Prefixes: Enter a comma-separated list of prefixes. Only variables starting with these prefixes will be considered.
   - Suffixes: Enter a comma-separated list of suffixes. The tool will filter in variables ending with these suffixes.
   - Both: If you choose both, you'll provide both prefixes and suffixes, allowing for highly specific variable filtering.
- Smart Orientation Adjustment: After variable selection, you'll input the expected dimension (e.g., 660) that represents the number of wavenumbers. This dimension helps OutlierStrip understand the data structure, ensuring that spectra are plotted with wavenumbers along the x-axis. It's a critical step for datasets where the orientation isn't standardized.
- Visualize Spectra: Upon selecting a variable, its spectral data is plotted in the main viewing area. This visual representation is key to identifying outliers—spectra that deviate significantly from the norm.
Interactive Plotting: indicating they've been selected for removal.
- Manually Mark and Remove Outliers: Click on individual spectra directly within the plot to mark them. Marked spectra might be highlighted in red colour. This manual selection process ensures you have full control over which data points are considered outliers. Once you've selected all outliers, click the 'Delete Marked Spectra' button to remove them from the dataset.

# Quick Start Guide:

1. Download the OutlierStrip repository to your local machine.
2. Launch MATLAB and navigate to OutlierStrip's folder.
3. Execute OutlierStrip from the MATLAB command line.
4. Engage with the GUI to filter, visualize, and cleanse your spectral data efficiently.


Licensing:
OutlierStrip is freely distributed under the MIT License, promoting open collaboration and modification.

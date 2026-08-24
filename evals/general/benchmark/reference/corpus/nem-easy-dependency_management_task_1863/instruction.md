# Dependency Management: Efficient Package Installation

You are working in a constrained environment with limited disk space (500MB available). Your task is to set up a Python environment with specific packages for data analysis while managing resources carefully.

## Your Task

1. **Install Python and pip**: First, ensure Python 3 and pip are installed on the system. If they're not present, install them using the system package manager.

2. **Install required packages**: Install the following Python packages with these specific versions:
   - `pandas==1.5.3`
   - `numpy==1.23.5`
   - `matplotlib==3.6.3`

3. **Manage disk space**: Due to the disk space constraint (500MB total), you must:
   - Use `--no-cache-dir` flag when installing packages to avoid caching large files
   - Clean up any temporary files or package caches after installation
   - Verify the installation doesn't exceed available space

4. **Create verification script**: Create a Python script at `/app/verify_installation.py` that:
   - Imports all three installed packages (pandas, numpy, matplotlib)
   - Creates a small test dataset (10x10 random numbers using numpy)
   - Creates a simple pandas DataFrame from this data
   - Generates a basic plot using matplotlib (don't display it, just save to file)
   - Saves the plot as `/app/test_plot.png`
   - Prints "All packages installed successfully" if everything works

5. **Write installation summary**: Create a file at `/app/installation_summary.txt` containing:
   - The versions of pandas, numpy, and matplotlib installed (one per line)
   - The total disk space used by Python packages (in MB, approximate is fine)
   - Whether the installation succeeded within the 500MB constraint (yes/no)

## Expected Outputs

- `/app/verify_installation.py` - Script that tests all three packages
- `/app/test_plot.png` - Generated plot file (should be created when script runs)
- `/app/installation_summary.txt` - Summary of installation with versions and space usage

## Verification

The system will test:
1. That all three packages can be imported without errors
2. That your verification script runs successfully
3. That the plot file was created
4. That the installation summary file contains correct version information

## Constraints
- You have only 500MB of disk space available
- Use `--no-cache-dir` flag to minimize disk usage during installation
- Clean up package caches after installation
- Install the exact versions specified
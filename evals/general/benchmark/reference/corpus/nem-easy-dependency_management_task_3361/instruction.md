# Disk-Constrained Environment Setup for Data Analysis

You're working in a disk-constrained environment (only 500MB free) and need to set up a Python environment for a legacy data analysis script. The script requires specific package versions to function correctly.

## Your Task

1. **Create an isolated environment**: Set up a Python virtual environment at `/app/data_env` to avoid conflicts with the system Python installation.

2. **Install required packages with disk constraints**:
   - Install `pandas==1.5.3` 
   - Install a compatible version of `numpy` (must be ≥1.21.0 and <2.0.0)
   - You MUST use disk-saving installation techniques since you have limited space
   - Install these packages in a way that minimizes disk usage during and after installation

3. **Create a verification script**: Create `/app/verify_install.py` that:
   - Imports both pandas and numpy
   - Prints the exact version of each package in this format:
     ```
     pandas version: X.Y.Z
     numpy version: A.B.C
     ```
   - Creates a simple 3x2 DataFrame with sample data and prints its shape in this format:
     ```
     DataFrame shape: (rows, columns)
     ```

4. **Clean up installation artifacts**: After installation, remove any unnecessary cache files to free up disk space.

## Expected Outputs

- Virtual environment directory: `/app/data_env/`
- Verification script: `/app/verify_install.py`
- Packages installed in the virtual environment (pandas 1.5.3, numpy compatible version)

## Success Criteria

1. The virtual environment at `/app/data_env` must exist and contain the packages
2. Running `/app/data_env/bin/python /app/verify_install.py` should:
   - Execute without errors
   - Print the exact version strings for pandas and numpy
   - Print the DataFrame shape as (3, 2)
3. The installation must respect disk constraints (use appropriate flags to minimize cache usage)

## Constraints

- You have limited disk space (500MB total)
- The script requires pandas exactly version 1.5.3
- numpy must be compatible with pandas 1.5.3 (≥1.21.0, <2.0.0)
- You must not install packages globally; use the virtual environment
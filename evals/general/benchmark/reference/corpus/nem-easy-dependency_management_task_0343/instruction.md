# Dependency Challenge: Lightweight Data Analysis Environment

You're working on a server with very limited disk space (500MB free). You need to set up a minimal Python environment for a data analysis script that requires array operations and basic plotting capabilities.

## Your Task

1. **Create an isolated environment** in `/app/venv` that avoids system-wide package conflicts
2. **Install specific package versions** to ensure compatibility:
   - A numerical computing library that provides array operations (version 1.24.3 or newer)
   - A plotting library that can create static visualizations (version 3.7.1 or newer)
3. **Use resource-aware installation** to minimize disk usage:
   - Disable package caching during installation
   - Clean up any temporary files after installation
4. **Create a verification script** at `/app/verify_install.py` that:
   - Imports both installed packages
   - Creates a 50x50 array of random numbers using the numerical library
   - Calculates and prints the mean of the array (should be between 0 and 1)
   - Creates a simple plot object using the plotting library (don't save it to disk)

## Constraints

- You cannot use more than 500MB of additional disk space
- The system starts with minimal Python 3.11 and pip installed
- You must isolate your packages from the system Python
- The verification script must run without errors using your environment

## Expected Outputs

- Virtual environment directory: `/app/venv/`
- Verification script: `/app/verify_install.py`
- When run, the script should print a number between 0 and 1 and exit with code 0

## Verification

Your solution will be tested with:
1. Check that packages are installed in the virtual environment
2. Run `/app/verify_install.py` with the virtual environment's Python
3. Verify output is a valid number between 0 and 1
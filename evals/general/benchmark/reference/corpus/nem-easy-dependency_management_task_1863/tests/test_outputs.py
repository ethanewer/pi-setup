import os
import subprocess
import sys
import json

def test_packages_installed():
    """Verify all three packages are installed and importable."""
    test_script = """
import pandas as pd
import numpy as np
import matplotlib
print(f"pandas: {pd.__version__}")
print(f"numpy: {np.__version__}")
print(f"matplotlib: {matplotlib.__version__}")
"""
    
    result = subprocess.run(
        [sys.executable, '-c', test_script],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Import failed: {result.stderr}"
    
    # Check versions are correct
    output = result.stdout.lower()
    assert "pandas: 1.5.3" in output or "1.5.3" in output, f"Wrong pandas version: {output}"
    assert "numpy: 1.23.5" in output or "1.23.5" in output, f"Wrong numpy version: {output}"
    assert "matplotlib: 3.6.3" in output or "3.6.3" in output, f"Wrong matplotlib version: {output}"

def test_verification_script():
    """Verify the verification script runs successfully."""
    script_path = "/app/verify_installation.py"
    
    # Check script exists
    assert os.path.exists(script_path), f"Script not found at {script_path}"
    
    # Run the script
    result = subprocess.run(
        [sys.executable, script_path],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Script failed: {result.stderr}"
    assert "All packages installed successfully" in result.stdout, "Success message not found"
    
    # Check plot was created
    plot_path = "/app/test_plot.png"
    assert os.path.exists(plot_path), f"Plot not created at {plot_path}"
    assert os.path.getsize(plot_path) > 0, "Plot file is empty"

def test_installation_summary():
    """Verify installation summary file exists and contains required information."""
    summary_path = "/app/installation_summary.txt"
    
    assert os.path.exists(summary_path), f"Summary file not found at {summary_path}"
    
    with open(summary_path, 'r') as f:
        content = f.read().lower()
    
    # Check for required information
    assert "pandas" in content, "pandas version not in summary"
    assert "numpy" in content, "numpy version not in summary"
    assert "matplotlib" in content, "matplotlib version not in summary"
    assert "1.5.3" in content, "pandas version 1.5.3 not found"
    assert "1.23.5" in content, "numpy version 1.23.5 not found"
    assert "3.6.3" in content, "matplotlib version 3.6.3 not found"
    assert "mb" in content, "Disk space measurement (MB) not in summary"
    assert "yes" in content or "no" in content, "Constraint check (yes/no) not in summary"

def test_disk_space_constraint():
    """Verify installation doesn't exceed reasonable disk usage."""
    # Check if pip cache was cleaned (approximate check)
    result = subprocess.run(
        ["du", "-sh", "/root/.cache/pip"],
        capture_output=True,
        text=True
    )
    
    # If pip cache exists, it should be small (under 50MB ideally)
    if result.returncode == 0 and result.stdout.strip():
        size_str = result.stdout.split()[0]
        # Convert to MB if ends with M, otherwise assume small
        if size_str.endswith('M'):
            size_mb = float(size_str[:-1])
            assert size_mb < 100, f"Pip cache too large: {size_mb}MB"
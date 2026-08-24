import os
import subprocess
import sys
import re

def test_virtual_environment_exists():
    """Verify virtual environment was created."""
    assert os.path.exists("/app/venv"), "Virtual environment directory not found"
    assert os.path.exists("/app/venv/bin/python"), "Virtual environment Python not found"
    
def test_packages_installed():
    """Verify required packages are installed in virtual environment."""
    # Use the virtual environment's pip to check installed packages
    pip_path = "/app/venv/bin/pip"
    assert os.path.exists(pip_path), "pip not found in virtual environment"
    
    # Check for numpy
    result = subprocess.run(
        [pip_path, "list", "--format=freeze"],
        capture_output=True,
        text=True
    )
    
    # Look for numpy and matplotlib
    installed_packages = result.stdout.lower()
    assert "numpy" in installed_packages, "numpy not installed"
    assert "matplotlib" in installed_packages, "matplotlib not installed"
    
    # Check versions
    numpy_match = re.search(r'numpy==(\d+\.\d+\.\d+)', result.stdout, re.IGNORECASE)
    matplotlib_match = re.search(r'matplotlib==(\d+\.\d+\.\d+)', result.stdout, re.IGNORECASE)
    
    if numpy_match:
        version_parts = [int(x) for x in numpy_match.group(1).split('.')]
        assert version_parts >= [1, 24, 3], f"numpy version {numpy_match.group(1)} < 1.24.3"
    
    if matplotlib_match:
        version_parts = [int(x) for x in matplotlib_match.group(1).split('.')]
        assert version_parts >= [3, 7, 1], f"matplotlib version {matplotlib_match.group(1)} < 3.7.1"

def test_verification_script_runs():
    """Verify the verification script executes successfully."""
    # Use virtual environment's Python
    python_path = "/app/venv/bin/python"
    assert os.path.exists(python_path), "Virtual environment Python not found"
    
    result = subprocess.run(
        [python_path, "/app/verify_install.py"],
        capture_output=True,
        text=True
    )
    
    # Check exit code
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    
    # Check output contains a number between 0 and 1
    output = result.stdout.strip()
    try:
        value = float(output)
        assert 0 <= value <= 1, f"Value {value} not between 0 and 1"
    except ValueError:
        assert False, f"Output '{output}' is not a valid number"

def test_script_imports_packages():
    """Verify script imports the required packages."""
    with open("/app/verify_install.py", "r") as f:
        content = f.read()
    
    # Check for imports (case insensitive)
    content_lower = content.lower()
    assert "import numpy" in content_lower or "from numpy" in content_lower
    assert "import matplotlib" in content_lower or "from matplotlib" in content_lower
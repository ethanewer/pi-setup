import os
import subprocess
import sys
import re

def test_virtual_environment_exists():
    """Verify the virtual environment directory exists."""
    assert os.path.exists('/app/data_env'), "Virtual environment directory not found"
    assert os.path.exists('/app/data_env/bin/python'), "Python not found in virtual environment"
    print("✓ Virtual environment exists")

def test_packages_installed():
    """Verify pandas and numpy are installed with correct versions."""
    # Run the verification script to check imports and versions
    result = subprocess.run(
        ['/app/data_env/bin/python', '/app/verify_install.py'],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Verification script failed: {result.stderr}"
    
    # Check for version outputs
    output = result.stdout
    
    # Check pandas version
    pandas_match = re.search(r'pandas version:\s*(\d+\.\d+\.\d+)', output)
    assert pandas_match, "Pandas version not found in output"
    pandas_version = pandas_match.group(1)
    assert pandas_version == '1.5.3', f"Expected pandas 1.5.3, got {pandas_version}"
    
    # Check numpy version
    numpy_match = re.search(r'numpy version:\s*(\d+\.\d+\.\d+)', output)
    assert numpy_match, "Numpy version not found in output"
    numpy_version = numpy_match.group(1)
    
    # Parse version components
    major, minor, patch = map(int, numpy_version.split('.'))
    
    # Check numpy compatibility with pandas 1.5.3
    assert major == 1, f"Numpy major version must be 1, got {major}"
    assert minor >= 21, f"Numpy version must be ≥1.21.0, got {numpy_version}"
    
    print(f"✓ Packages installed: pandas {pandas_version}, numpy {numpy_version}")

def test_dataframe_shape():
    """Verify the DataFrame is created with correct shape."""
    result = subprocess.run(
        ['/app/data_env/bin/python', '/app/verify_install.py'],
        capture_output=True,
        text=True
    )
    
    output = result.stdout
    
    # Check for shape output
    shape_match = re.search(r'DataFrame shape:\s*\((\d+),\s*(\d+)\)', output)
    assert shape_match, "DataFrame shape not found in output"
    
    rows, cols = int(shape_match.group(1)), int(shape_match.group(2))
    assert rows == 3, f"Expected 3 rows, got {rows}"
    assert cols == 2, f"Expected 2 columns, got {cols}"
    
    print(f"✓ DataFrame shape correct: ({rows}, {cols})")

def test_script_completes():
    """Verify the entire verification script runs successfully."""
    result = subprocess.run(
        ['/app/data_env/bin/python', '/app/verify_install.py'],
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"
    
    # Check all required lines are present
    output = result.stdout
    assert 'pandas version:' in output, "Pandas version line missing"
    assert 'numpy version:' in output, "Numpy version line missing"
    assert 'DataFrame shape:' in output, "DataFrame shape line missing"
    
    print("✓ Verification script completes successfully")
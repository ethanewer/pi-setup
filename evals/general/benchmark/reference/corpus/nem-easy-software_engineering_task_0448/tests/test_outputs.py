import os
import json
import re
import pytest

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/clean_requirements.txt'), "clean_requirements.txt not found"
    assert os.path.exists('/app/summary.json'), "summary.json not found"

def test_clean_requirements_format():
    """Verify cleaned requirements file has correct format."""
    with open('/app/clean_requirements.txt', 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    
    # Check each line has package==version format
    pattern = re.compile(r'^[a-zA-Z0-9_-]+==\d+(\.\d+)*(\.[a-zA-Z0-9]+)?$')
    for line in lines:
        assert pattern.match(line), f"Invalid format: {line}"
    
    # Check alphabetical order
    packages = [line.split('==')[0] for line in lines]
    assert packages == sorted(packages), "Packages not in alphabetical order"

def test_summary_json_structure():
    """Verify summary JSON has correct structure and data types."""
    with open('/app/summary.json', 'r') as f:
        summary = json.load(f)
    
    required_keys = {"original_count", "cleaned_count", "duplicates_removed", "packages"}
    assert set(summary.keys()) == required_keys, f"Missing keys in summary: {required_keys - set(summary.keys())}"
    
    assert isinstance(summary["original_count"], int), "original_count should be integer"
    assert isinstance(summary["cleaned_count"], int), "cleaned_count should be integer"
    assert isinstance(summary["duplicates_removed"], int), "duplicates_removed should be integer"
    assert isinstance(summary["packages"], list), "packages should be a list"
    
    # Check packages are sorted
    assert summary["packages"] == sorted(summary["packages"]), "packages list not sorted"

def test_requirements_processing():
    """Verify requirements were processed correctly."""
    # Read original file
    with open('/app/requirements.txt', 'r') as f:
        original_lines = f.readlines()
    
    # Read cleaned file
    with open('/app/clean_requirements.txt', 'r') as f:
        cleaned_lines = [line.strip() for line in f if line.strip()]
    
    # Read summary
    with open('/app/summary.json', 'r') as f:
        summary = json.load(f)
    
    # Check counts match
    assert summary["original_count"] == len(original_lines), "original_count doesn't match"
    assert summary["cleaned_count"] == len(cleaned_lines), "cleaned_count doesn't match"
    
    # Calculate expected duplicates
    package_names = []
    for line in original_lines:
        line = line.strip()
        if line and not line.startswith('#'):
            # Extract package name (before any version specifier or comment)
            pkg = line.split()[0].split('<')[0].split('>')[0].split('~')[0].split('=')[0]
            package_names.append(pkg)
    
    unique_packages = []
    seen = set()
    for pkg in package_names:
        if pkg not in seen:
            seen.add(pkg)
            unique_packages.append(pkg)
    
    expected_duplicates = len(package_names) - len(unique_packages)
    assert summary["duplicates_removed"] == expected_duplicates, "duplicates_removed doesn't match"
    
    # Check packages list matches cleaned file
    cleaned_packages = [line.split('==')[0] for line in cleaned_lines]
    assert summary["packages"] == sorted(cleaned_packages), "packages list doesn't match cleaned requirements"

def test_version_normalization():
    """Verify version specifiers were normalized correctly."""
    with open('/app/clean_requirements.txt', 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    
    # Check all lines use == format
    for line in lines:
        assert '==' in line, f"Line doesn't use == format: {line}"
        parts = line.split('==')
        assert len(parts) == 2, f"Invalid format: {line}"
        
        # Version should be valid (not empty)
        assert parts[1], f"Empty version: {line}"
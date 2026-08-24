import os
import json
import subprocess
import sys

def test_output_files_exist():
    """Verify both output files were created."""
    assert os.path.exists('/app/package_summary.txt'), "package_summary.txt not found"
    assert os.path.exists('/app/debug_log.txt'), "debug_log.txt not found"

def test_summary_format_correct():
    """Verify summary file has correct format and content."""
    with open('/app/package_summary.txt', 'r') as f:
        lines = f.readlines()
    
    # Check structure
    assert len(lines) >= 7, f"Expected at least 7 lines, got {len(lines)}"
    
    # Parse lines
    lines = [line.strip() for line in lines]
    
    # Check required sections
    assert lines[0].startswith("Total packages checked:"), "Missing total packages line"
    assert lines[1].startswith("Packages installed:"), "Missing installed count line"
    assert lines[2].startswith("Packages missing:"), "Missing missing count line"
    assert lines[3] == "Missing packages:", "Missing packages header not found"
    
    # Extract counts
    total_checked = int(lines[0].split(":")[1].strip())
    installed = int(lines[1].split(":")[1].strip())
    missing = int(lines[2].split(":")[1].strip())
    
    # Validate counts are consistent
    assert total_checked == 7, f"Expected 7 packages, got {total_checked}"
    assert installed + missing == total_checked, "Counts don't add up"
    
    # Check missing packages list matches count
    missing_list = lines[4:] if len(lines) > 4 else []
    assert len(missing_list) == missing, f"Missing list length {len(missing_list)} doesn't match count {missing}"
    
    # Verify specific packages that should be missing
    assert "nonexistent_package_123" in missing_list, "Expected nonexistent_package_123 in missing list"

def test_debug_log_content():
    """Verify debug log contains appropriate content."""
    with open('/app/debug_log.txt', 'r') as f:
        content = f.read().strip()
    
    # Either contains error messages or success message
    assert len(content) > 0, "Debug log is empty"
    
    # If no errors, should contain success message
    if "No errors encountered" in content:
        # Verify script ran without errors
        pass
    else:
        # Should contain actual error output
        assert "Error" in content or "Traceback" in content or "exception" in content.lower()

def test_script_runs_without_crash():
    """Verify the fixed script runs without crashing."""
    # Run the script and check exit code
    result = subprocess.run([sys.executable, '/app/install_check.py'], 
                          capture_output=True, text=True, timeout=10)
    
    assert result.returncode == 0, f"Script crashed with exit code {result.returncode}"
    
    # Check stderr is empty or contains only expected warnings
    if result.stderr:
        # Allow ImportWarning or DeprecationWarning but not errors
        assert "Error" not in result.stderr, f"Unexpected error in stderr: {result.stderr}"

def test_json_config_parsed_correctly():
    """Verify the configuration file was parsed correctly."""
    # Read original config
    with open('/app/packages_config.json', 'r') as f:
        config = json.load(f)
    
    # Read summary and verify it matches config
    with open('/app/package_summary.txt', 'r') as f:
        summary = f.read()
    
    required_packages = config['required_packages']
    
    # Check all packages from config are accounted for
    for package in required_packages:
        # Each package should appear in summary (either installed or missing)
        # Built-in packages like json, os, sys won't appear as missing
        if package not in ['json', 'os', 'sys']:
            assert package in summary, f"Package {package} not found in summary"
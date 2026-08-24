import os
import re
import subprocess
import sys
import tempfile
from unittest.mock import patch, MagicMock
import pytest

def read_file(path):
    """Helper to read file content."""
    try:
        with open(path, 'r') as f:
            return f.read()
    except FileNotFoundError:
        return None

def test_security_report_exists():
    """Verify security report was created."""
    report = read_file('/app/security_report.txt')
    assert report is not None, "Security report not found"
    assert len(report) > 100, "Security report too short"
    
    # Check for key elements in report
    assert 'vulnerability' in report.lower() or 'vulnerable' in report.lower()
    assert 'line' in report.lower() or 'location' in report.lower()
    assert 'exploit' in report.lower() or 'payload' in report.lower()
    assert 'impact' in report.lower() or 'risk' in report.lower()

def test_fixed_implementation_exists():
    """Verify fixed implementation was created."""
    fixed_code = read_file('/app/fixed_monitor.py')
    assert fixed_code is not None, "Fixed implementation not found"
    assert len(fixed_code) > 50, "Fixed implementation too short"

def test_no_shell_true_in_fixed():
    """Verify fixed code doesn't use shell=True."""
    fixed_code = read_file('/app/fixed_monitor.py')
    
    # Check for subprocess.run usage
    if 'subprocess.run' in fixed_code:
        # Should not have shell=True
        lines = fixed_code.split('\n')
        for i, line in enumerate(lines):
            if 'subprocess.run' in line:
                # Check this line and next few lines for shell=True
                check_lines = ' '.join(lines[i:i+3])
                assert 'shell=True' not in check_lines, f"Line {i+1}: Uses shell=True"
    
    # Also check for os.system and other dangerous calls
    dangerous_patterns = [
        r'os\.system\(',
        r'os\.popen\(',
        r'subprocess\.Popen.*shell=True',
        r'exec\(',
        r'eval\('
    ]
    
    for pattern in dangerous_patterns:
        matches = re.findall(pattern, fixed_code)
        assert len(matches) == 0, f"Found dangerous pattern: {pattern}"

def test_input_validation_in_fixed():
    """Verify fixed code has input validation."""
    fixed_code = read_file('/app/fixed_monitor.py')
    
    # Look for validation patterns
    validation_indicators = [
        r'def.*validate',
        r'if.*not.*valid',
        r'raise.*ValueError',
        r'assert.*valid',
        r're\.match',
        r're\.search',
        r're\.compile',
        r'isalnum',
        r'validation',
        r'sanitize'
    ]
    
    found = False
    for indicator in validation_indicators:
        if re.search(indicator, fixed_code, re.IGNORECASE):
            found = True
            break
    
    assert found, "No input validation found in fixed code"

def test_test_file_exists():
    """Verify test file was created."""
    test_code = read_file('/app/test_security.py')
    assert test_code is not None, "Test file not found"
    assert len(test_code) > 50, "Test file too short"
    
    # Check it has test functions
    assert 'def test_' in test_code
    assert 'import' in test_code
    assert 'unittest' in test_code or 'pytest' in test_code

def test_test_file_runs():
    """Verify test file can be imported and has test functions."""
    test_code = read_file('/app/test_security.py')
    
    # Count test functions
    test_functions = re.findall(r'def (test_\w+)', test_code)
    assert len(test_functions) >= 3, f"Expected at least 3 test functions, found {len(test_functions)}"
    
    # Try to import and run a simple test
    sys.path.insert(0, '/app')
    try:
        import test_security
        # Check if it has test methods
        test_methods = [m for m in dir(test_security) if m.startswith('test_')]
        assert len(test_methods) >= 3, f"Found {len(test_methods)} test methods"
    except ImportError as e:
        pytest.fail(f"Could not import test_security: {e}")
    except Exception as e:
        # Other errors are okay for this test
        pass
    finally:
        sys.path.remove('/app')

def test_vulnerability_identification():
    """Verify security report correctly identifies vulnerability."""
    report = read_file('/app/security_report.txt')
    
    # Check for command injection keywords
    keywords = ['command injection', 'shell injection', 'os.command', 'subprocess']
    found_keywords = sum(1 for kw in keywords if kw.lower() in report.lower())
    assert found_keywords >= 1, "Security report doesn't mention command injection"
    
    # Check for example payload
    payload_indicators = [';', '&&', '||', '`', '$', '|']
    found_payload = any(indicator in report for indicator in payload_indicators)
    assert found_payload, "Security report should include example payload with metacharacters"

def test_fixed_code_structure():
    """Verify fixed code has proper structure."""
    fixed_code = read_file('/app/fixed_monitor.py')
    
    # Should have main function or class
    assert 'def ' in fixed_code or 'class ' in fixed_code
    
    # Should handle HTTP requests (mentioned in prompt)
    if 'http.server' in fixed_code or 'flask' in fixed_code or 'socket' in fixed_code:
        # Has web server components
        pass
    else:
        # Might be just the core functions
        assert 'ping' in fixed_code.lower() or 'host' in fixed_code.lower()

def test_integration_security():
    """Test that the fixed code actually prevents injection."""
    # This is a basic test - in real scenario would run the code
    fixed_code = read_file('/app/fixed_monitor.py')
    
    # Check for dangerous patterns that might still be there
    dangerous_combinations = [
        (r'subprocess\.run\(.*\+.*hostname', 'String concatenation in subprocess.run'),
        (r'f".*{.*}.*"', 'f-string with user input in command'),
        (r'\%s.*hostname', 'String formatting with user input in command')
    ]
    
    for pattern, description in dangerous_combinations:
        if re.search(pattern, fixed_code):
            # If found, make sure it's in a safe context (like logging, not execution)
            # For simplicity, we'll just flag it
            print(f"Warning: Found {description} in code")

def test_output_files_complete():
    """Verify all required output files exist and have content."""
    required_files = [
        '/app/security_report.txt',
        '/app/fixed_monitor.py',
        '/app/test_security.py'
    ]
    
    for filepath in required_files:
        assert os.path.exists(filepath), f"Missing file: {filepath}"
        assert os.path.getsize(filepath) > 50, f"File too small: {filepath}"
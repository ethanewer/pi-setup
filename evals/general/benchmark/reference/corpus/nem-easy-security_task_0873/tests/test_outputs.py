import os
import json
import base64
import hashlib

def test_report_structure():
    """Verify the security report has correct structure and counts."""
    report_path = "/app/output/security_report.json"
    
    assert os.path.exists(report_path), f"Report file not found at {report_path}"
    
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    # Check required fields
    required_fields = ["total_passwords_checked", "weak_passwords_count", 
                      "weak_passwords", "strong_passwords_count"]
    for field in required_fields:
        assert field in report, f"Missing field in report: {field}"
    
    # Check counts are consistent
    assert report["weak_passwords_count"] == len(report["weak_passwords"]), \
        "Weak password count doesn't match list length"
    
    assert report["total_passwords_checked"] == report["weak_passwords_count"] + report["strong_passwords_count"], \
        "Total doesn't equal weak + strong"
    
    # Check weak password entries have required fields
    for weak_pw in report["weak_passwords"]:
        required_pw_fields = ["file", "line", "password", "violations"]
        for field in required_pw_fields:
            assert field in weak_pw, f"Weak password entry missing field: {field}"
        assert isinstance(weak_pw["violations"], list), "Violations should be a list"

def test_weak_passwords_file():
    """Verify weak passwords file contains correct sorted passwords."""
    weak_file = "/app/output/weak_passwords.txt"
    report_file = "/app/output/security_report.json"
    
    assert os.path.exists(weak_file), f"Weak passwords file not found at {weak_file}"
    assert os.path.exists(report_file), f"Report file not found at {report_file}"
    
    with open(report_file, 'r') as f:
        report = json.load(f)
    
    # Get weak passwords from report
    weak_from_report = sorted([entry["password"] for entry in report["weak_passwords"]])
    
    # Read weak passwords file
    with open(weak_file, 'r') as f:
        weak_from_file = [line.strip() for line in f if line.strip()]
    
    # Compare
    assert len(weak_from_file) == len(weak_from_report), \
        f"File has {len(weak_from_file)} passwords, report has {len(weak_from_report)}"
    
    for i, (file_pw, report_pw) in enumerate(zip(weak_from_file, weak_from_report)):
        assert file_pw == report_pw, f"Mismatch at position {i}: file='{file_pw}', report='{report_pw}'"

def test_password_validation():
    """Verify specific password validations are correct."""
    # Test some known passwords from test data
    test_cases = [
        # (base64_encoded, username, expected_violations_or_none)
        ("UGFzc3dvcmQxMjM=", "test", ["too_short", "no_special_char"]),  # "Password123"
        ("YWxpY2VzUEFTUzEyMyE=", "alice", ["contains_username"]),  # "alicesPASS123!"
        ("U3Ryb25nUCFzc3dvcmQxMjM=", "bob", None),  # "StrongP@ssword123"
        ("MTIzNDU2Nzg=", "user", ["too_short", "no_upper", "no_lower", "no_special_char"]),  # "12345678"
    ]
    
    report_path = "/app/output/security_report.json"
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    # Find test passwords in report
    for encoded, username, expected in test_cases:
        password = base64.b64decode(encoded).decode('utf-8')
        
        # Look for this password in weak passwords list
        found = False
        for entry in report["weak_passwords"]:
            if entry["password"] == password:
                if expected is not None:
                    # Check violations match expected
                    assert set(entry["violations"]) == set(expected), \
                        f"Password '{password}' violations don't match. Got {entry['violations']}, expected {expected}"
                else:
                    assert False, f"Password '{password}' should not be in weak list"
                found = True
                break
        
        if expected is None and not found:
            # Password should be strong (not in weak list)
            pass  # This is correct
        elif expected is not None and not found:
            assert False, f"Weak password '{password}' not found in report"

def test_file_processing():
    """Verify all .pw files were processed."""
    import glob
    
    # Count expected passwords from test data
    pw_files = glob.glob("/app/password_data/**/*.pw", recursive=True)
    total_lines = 0
    for file in pw_files:
        with open(file, 'r') as f:
            total_lines += len([line for line in f if line.strip()])
    
    report_path = "/app/output/security_report.json"
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    assert report["total_passwords_checked"] == total_lines, \
        f"Report says {report['total_passwords_checked']} passwords checked, but files contain {total_lines} lines"

def test_output_correct():
    """Main test combining all verification."""
    # Run all verification tests
    test_report_structure()
    test_weak_passwords_file()
    test_password_validation()
    test_file_processing()
    
    print("All tests passed!")
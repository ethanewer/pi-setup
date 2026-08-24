import os
import json
import re
import hashlib
from pathlib import Path

def test_security_report_exists():
    """Verify the security report file was created."""
    report_path = "/app/output/security_report.json"
    assert os.path.exists(report_path), f"Report file not found at {report_path}"
    print("✓ Report file exists")

def test_report_structure():
    """Verify the report has the correct structure."""
    with open("/app/output/security_report.json", "r") as f:
        report = json.load(f)
    
    # Check required fields
    required_fields = [
        "total_files_scanned",
        "total_secrets_found", 
        "valid_secrets_by_type",
        "invalid_secrets_by_type",
        "validation_errors"
    ]
    
    for field in required_fields:
        assert field in report, f"Missing field: {field}"
    
    # Check type-specific fields
    secret_types = ["api_key", "password", "access_token", "database_url"]
    for secret_type in secret_types:
        assert secret_type in report["valid_secrets_by_type"], f"Missing valid_secrets_by_type[{secret_type}]"
        assert secret_type in report["invalid_secrets_by_type"], f"Missing invalid_secrets_by_type[{secret_type}]"
    
    print("✓ Report structure is correct")

def test_secret_counts():
    """Verify the secret counts are accurate based on test files."""
    with open("/app/output/security_report.json", "r") as f:
        report = json.load(f)
    
    # Based on our test files, we should find:
    # - 3 api_key entries (2 valid, 1 invalid)
    # - 4 password entries (1 valid, 3 invalid) 
    # - 3 access_token entries (2 valid, 1 invalid)
    # - 2 database_url entries (2 valid, 0 invalid)
    # Total files: 5, Total secrets: 12
    
    assert report["total_files_scanned"] == 5, f"Expected 5 files, got {report['total_files_scanned']}"
    assert report["total_secrets_found"] == 12, f"Expected 12 secrets, got {report['total_secrets_found']}"
    
    assert report["valid_secrets_by_type"]["api_key"] == 2, f"Expected 2 valid api_keys"
    assert report["invalid_secrets_by_type"]["api_key"] == 1, f"Expected 1 invalid api_key"
    
    assert report["valid_secrets_by_type"]["password"] == 1, f"Expected 1 valid password"
    assert report["invalid_secrets_by_type"]["password"] == 3, f"Expected 3 invalid passwords"
    
    assert report["valid_secrets_by_type"]["access_token"] == 2, f"Expected 2 valid access_tokens"
    assert report["invalid_secrets_by_type"]["access_token"] == 1, f"Expected 1 invalid access_token"
    
    assert report["valid_secrets_by_type"]["database_url"] == 2, f"Expected 2 valid database_urls"
    assert report["invalid_secrets_by_type"]["database_url"] == 0, f"Expected 0 invalid database_urls"
    
    print("✓ Secret counts are accurate")

def test_password_validation():
    """Verify password validation rules are correctly applied."""
    with open("/app/output/security_report.json", "r") as f:
        report = json.load(f)
    
    # Check that validation errors include password issues
    password_errors = [err for err in report["validation_errors"] if "password" in err.lower()]
    assert len(password_errors) >= 2, f"Expected at least 2 password validation errors"
    
    # Check for specific expected errors
    error_messages = " ".join(report["validation_errors"]).lower()
    assert "too short" in error_messages or "length" in error_messages, "Missing length validation error"
    assert "uppercase" in error_messages or "lowercase" in error_messages or "digit" in error_messages or "special" in error_messages, "Missing complexity validation error"
    
    print("✓ Password validation rules are applied")

def test_hex_validation():
    """Verify hex token validation is correct."""
    with open("/app/output/security_report.json", "r") as f:
        report = json.load(f)
    
    # Check for hex validation error
    hex_errors = [err for err in report["validation_errors"] if "hex" in err.lower() or "64" in err]
    assert len(hex_errors) >= 1, f"Expected at least 1 hex validation error"
    
    print("✓ Hex token validation is correct")

def test_report_integrity():
    """Verify the report is internally consistent."""
    with open("/app/output/security_report.json", "r") as f:
        report = json.load(f)
    
    # Total secrets should equal sum of valid + invalid
    total_valid = sum(report["valid_secrets_by_type"].values())
    total_invalid = sum(report["invalid_secrets_by_type"].values())
    total_calculated = total_valid + total_invalid
    
    assert report["total_secrets_found"] == total_calculated, \
        f"Total secrets mismatch: {report['total_secrets_found']} != {total_calculated}"
    
    print("✓ Report integrity check passed")
import os
import yaml
import json
import pytest
from pathlib import Path

def load_yaml(filepath):
    """Load YAML file safely."""
    with open(filepath, 'r') as f:
        return yaml.safe_load(f)

def load_json(filepath):
    """Load JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)

def test_security_report_exists():
    """Verify security report was generated."""
    report_path = "/app/security_report.json"
    assert os.path.exists(report_path), f"Security report not found at {report_path}"
    
    # Test JSON is valid
    report = load_json(report_path)
    assert isinstance(report, dict), "Report should be a JSON object"
    assert "findings" in report, "Report missing 'findings' key"
    assert "summary" in report, "Report missing 'summary' key"
    
    # Test findings structure
    for finding in report["findings"]:
        assert "category" in finding, "Finding missing 'category'"
        assert "location" in finding, "Finding missing 'location'"
        assert "issue" in finding, "Finding missing 'issue'"
        assert "recommendation" in finding, "Finding missing 'recommendation'"
        assert finding["category"] in ["CRITICAL", "HIGH", "MEDIUM", "LOW"], \
            f"Invalid category: {finding['category']}"
    
    # Test summary structure
    summary = report["summary"]
    required_keys = ["critical_count", "high_count", "medium_count", "low_count", "total_findings"]
    for key in required_keys:
        assert key in summary, f"Summary missing '{key}'"
        assert isinstance(summary[key], int), f"{key} should be integer"

def test_fixed_config_exists():
    """Verify fixed configuration was generated."""
    fixed_path = "/app/config_fixed.yaml"
    assert os.path.exists(fixed_path), f"Fixed config not found at {fixed_path}"
    
    # Test YAML is valid
    config = load_yaml(fixed_path)
    assert isinstance(config, dict), "Config should be a YAML object"

def test_vulnerabilities_identified():
    """Verify specific vulnerabilities were identified in the report."""
    report = load_json("/app/security_report.json")
    config = load_yaml("/app/config.yaml")
    
    # Check for hardcoded password (should be CRITICAL)
    hardcoded_passwords = []
    if "database" in config and "password" in config["database"]:
        password = config["database"]["password"]
        if password and password != "":  # Check if password exists and is non-empty
            hardcoded_passwords.append("database.password")
    
    # Check if any hardcoded passwords were found in report
    password_found = False
    for finding in report["findings"]:
        if finding["location"] in hardcoded_passwords:
            password_found = True
            assert finding["category"] == "CRITICAL", \
                f"Hardcoded password should be CRITICAL, got {finding['category']}"
            break
    
    if hardcoded_passwords:
        assert password_found, f"Hardcoded password not identified: {hardcoded_passwords}"
    
    # Check summary counts match findings
    counts = {
        "CRITICAL": 0,
        "HIGH": 0,
        "MEDIUM": 0,
        "LOW": 0
    }
    
    for finding in report["findings"]:
        counts[finding["category"]] += 1
    
    summary = report["summary"]
    assert counts["CRITICAL"] == summary["critical_count"], "CRITICAL count mismatch"
    assert counts["HIGH"] == summary["high_count"], "HIGH count mismatch"
    assert counts["MEDIUM"] == summary["medium_count"], "MEDIUM count mismatch"
    assert counts["LOW"] == summary["low_count"], "LOW count mismatch"
    assert len(report["findings"]) == summary["total_findings"], "Total findings mismatch"

def test_vulnerabilities_fixed():
    """Verify vulnerabilities were fixed in the corrected configuration."""
    original = load_yaml("/app/config.yaml")
    fixed = load_yaml("/app/config_fixed.yaml")
    report = load_json("/app/security_report.json")
    
    # Check that non-security settings are preserved
    if "database" in original:
        if "host" in original["database"]:
            assert fixed["database"]["host"] == original["database"]["host"], \
                "Database host should be unchanged"
        if "port" in original["database"]:
            assert fixed["database"]["port"] == original["database"]["port"], \
                "Database port should be unchanged"
    
    # Apply fixes based on report findings
    for finding in report["findings"]:
        location = finding["location"]
        
        # Navigate to the location in the config
        parts = location.split(".")
        config_section = fixed
        
        # Navigate through nested structure
        for i, part in enumerate(parts[:-1]):
            if part in config_section:
                config_section = config_section[part]
            else:
                # If key doesn't exist, check if it was added as a new security setting
                if i == len(parts) - 2:
                    # This might be a new key added for security
                    break
                else:
                    pytest.fail(f"Key {part} not found in fixed config at location {location}")
        
        last_part = parts[-1]
        
        # Check specific fixes based on recommendations
        if "password" in location.lower():
            # Password should be changed from the original
            if last_part in config_section:
                assert config_section[last_part] != original.get("database", {}).get("password", ""), \
                    "Password should be changed from original weak value"
        
        elif "debug_mode" in location:
            if last_part in config_section:
                assert config_section[last_part] == False, "Debug mode should be disabled"
        
        elif "cookie_secure" in location:
            if last_part in config_section:
                assert config_section[last_part] == True, "Cookies should be secure (HTTPS only)"
        
        elif "cors_origin" in location:
            if last_part in config_section:
                assert config_section[last_part] != "*", "CORS origin should not be wildcard"
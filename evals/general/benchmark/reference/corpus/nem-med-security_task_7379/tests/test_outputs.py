import os
import json
import subprocess
import time
import requests
from pathlib import Path
import sqlite3
import tempfile
import pytest

def test_exploit_works_on_vulnerable():
    """Test that the exploit successfully demonstrates vulnerabilities on vulnerable API."""
    # Start vulnerable API
    vuln_proc = subprocess.Popen(
        ["python", "/app/vulnerable_api.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Wait for API to start
    time.sleep(2)
    
    try:
        # Run exploit
        result = subprocess.run(
            ["python", "/app/exploit.py"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Check exploit found SQL injection
        assert "SQL Injection successful" in result.stdout or "Extracted data" in result.stdout
        # Check exploit found XSS vulnerability  
        assert "XSS payload" in result.stdout or "Script injection" in result.stdout
        # Check exploit found IDOR
        assert "IDOR successful" in result.stdout or "Unauthorized access" in result.stdout
        
    finally:
        # Clean up
        vuln_proc.terminate()
        vuln_proc.wait()

def test_exploit_fails_on_fixed():
    """Test that the same exploit fails on the fixed API."""
    # Start fixed API
    fixed_proc = subprocess.Popen(
        ["python", "/app/fixed_api.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Wait for API to start
    time.sleep(2)
    
    try:
        # Run exploit against fixed API
        result = subprocess.run(
            ["python", "/app/exploit.py"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Verify SQL injection is blocked
        assert "SQL Injection successful" not in result.stdout
        assert "Error" in result.stdout or "Blocked" in result.stdout or "Invalid" in result.stdout
        
        # Verify IDOR is blocked
        assert "IDOR successful" not in result.stdout
        
    finally:
        # Clean up
        fixed_proc.terminate()
        fixed_proc.wait()

def test_fixed_api_maintains_functionality():
    """Test that fixed API still works for legitimate use cases."""
    fixed_proc = subprocess.Popen(
        ["python", "/app/fixed_api.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    time.sleep(2)
    
    try:
        # Test legitimate login
        resp = requests.post("http://localhost:8080/login", 
                           json={"username": "user1", "password": "password123"})
        assert resp.status_code in [200, 401]  # Either success or proper auth failure
        
        # Test legitimate product search
        resp = requests.get("http://localhost:8080/products?search=laptop")
        assert resp.status_code == 200
        
        # Test legitimate user data access (own profile)
        resp = requests.get("http://localhost:8080/profile/1")
        assert resp.status_code in [200, 401, 403]  # Either success or proper auth error
        
    finally:
        fixed_proc.terminate()
        fixed_proc.wait()

def test_security_report_exists():
    """Test that security report is generated with correct structure."""
    report_path = Path("/app/security_report.json")
    assert report_path.exists(), "Security report not found"
    
    with open(report_path) as f:
        report = json.load(f)
    
    # Check structure
    assert "vulnerabilities" in report
    assert "proof_of_concept" in report
    assert "fixes_applied" in report
    assert "verification" in report
    
    # Verify vulnerabilities are identified
    vulnerabilities = report["vulnerabilities"]
    vuln_types = [v["type"].lower() for v in vulnerabilities]
    
    assert any("sql" in vtype for vtype in vuln_types), "SQL injection not identified"
    assert any("xss" in vtype for vtype in vuln_types), "XSS not identified"
    assert any("idor" in vtype for vtype in vuln_types or "direct" in vtype), "IDOR not identified"
    
    # Verify fixes are documented
    assert len(report["fixes_applied"]) >= 3, "Not enough fixes documented"

def test_fixed_code_uses_safe_practices():
    """Test that fixed code uses secure coding practices."""
    with open("/app/fixed_api.py") as f:
        fixed_code = f.read()
    
    # Check for parameterized queries
    assert "?" in fixed_code or "%s" in fixed_code or "execute(" in fixed_code, "No parameterized queries found"
    
    # Check for input validation
    assert "validate" in fixed_code.lower() or "sanitize" in fixed_code.lower(), "No input validation found"
    
    # Check for authorization checks
    assert "authorize" in fixed_code.lower() or "permission" in fixed_code.lower() or "check" in fixed_code.lower(), "No authorization checks found"
    
    # Check for escaping
    assert "escape" in fixed_code.lower() or "html" in fixed_code.lower(), "No output escaping found"
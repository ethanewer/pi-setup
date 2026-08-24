import os
import json
import sqlite3
import hashlib
import secrets
import subprocess
import time
import requests
import tempfile
from pathlib import Path
import pytest

def start_app(app_path, port=8080):
    """Start the application and wait for it to be ready."""
    try:
        # Kill any existing process on the port
        subprocess.run(['fuser', '-k', f'{port}/tcp'], capture_output=True)
        time.sleep(1)
        
        # Start the application
        proc = subprocess.Popen(['python3', app_path], 
                              stdout=subprocess.PIPE, 
                              stderr=subprocess.PIPE)
        time.sleep(2)  # Give it time to start
        return proc
    except Exception as e:
        print(f"Failed to start app: {e}")
        return None

def test_security_report_exists():
    """Verify the security report is created with proper format."""
    report_path = '/app/security_report.json'
    assert os.path.exists(report_path), f"Security report not found at {report_path}"
    
    with open(report_path, 'r') as f:
        report = json.load(f)
    
    # Check structure
    assert 'vulnerabilities' in report
    assert 'summary' in report
    assert isinstance(report['vulnerabilities'], list)
    
    # Check summary
    assert 'total_vulnerabilities' in report['summary']
    assert report['summary']['total_vulnerabilities'] >= 3
    
    # Check at least one critical vulnerability
    critical_found = any(v.get('severity') == 'critical' for v in report['vulnerabilities'])
    assert critical_found, "No critical vulnerability found in report"
    
    # Check each vulnerability has required fields
    for vuln in report['vulnerabilities']:
        assert 'type' in vuln
        assert 'location' in vuln
        assert 'description' in vuln
        assert 'severity' in vuln
        assert 'exploit_scenario' in vuln

def test_fixed_app_exists():
    """Verify the fixed application exists."""
    fixed_path = '/app/fixed_auth.py'
    assert os.path.exists(fixed_path), f"Fixed app not found at {fixed_path}"
    
    # Check it's not identical to vulnerable app
    with open('/app/vulnerable_auth.py', 'r') as f:
        vulnerable_content = f.read()
    with open(fixed_path, 'r') as f:
        fixed_content = f.read()
    
    assert vulnerable_content != fixed_content, "Fixed app is identical to vulnerable app"

def test_sql_injection_fixed():
    """Test that SQL injection vulnerabilities are fixed."""
    # Start the fixed application
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Test SQL injection attempt
        test_cases = [
            ("admin' OR '1'='1", "password"),
            ("admin", "' OR '1'='1"),
            ("' UNION SELECT 1,2,3 --", "anything"),
        ]
        
        for username, password in test_cases:
            response = requests.post('http://localhost:8080/login',
                                   json={'username': username, 'password': password},
                                   timeout=2)
            
            # Should not return success for injection attempts
            # Either fails or returns generic error
            data = response.json()
            if response.status_code == 200:
                assert data.get('success') is False, f"SQL injection succeeded with {username}:{password}"
    
    finally:
        proc.terminate()
        proc.wait()

def test_password_hashing_secure():
    """Test that passwords are properly hashed with salt."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Register a test user
        username = f"test_user_{secrets.token_hex(4)}"
        password = "SecurePass123!"
        
        response = requests.post('http://localhost:8080/register',
                               json={'username': username, 'password': password},
                               timeout=2)
        
        # Check the database to see how password is stored
        db_path = '/app/users.db'
        if os.path.exists(db_path):
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT password FROM users WHERE username = ?", (username,))
            result = cursor.fetchone()
            conn.close()
            
            if result:
                stored_hash = result[0]
                # Check it's not plain text
                assert stored_hash != password, "Password stored in plain text"
                # Check it's not a simple MD5 or SHA1
                assert not stored_hash.startswith('$1$'), "Using weak MD5 hashing"
                # Should be a proper hash with salt (like bcrypt or PBKDF2)
                assert len(stored_hash) > 32, "Hash appears too short"
    
    finally:
        proc.terminate()
        proc.wait()

def test_session_management_secure():
    """Test that session tokens are securely generated and managed."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Test login to get session token
        response = requests.post('http://localhost:8080/login',
                               json={'username': 'testuser', 'password': 'testpass'},
                               timeout=2)
        
        if response.status_code == 200:
            data = response.json()
            if data.get('success'):
                token = data.get('token')
                if token:
                    # Check token is sufficiently random
                    assert len(token) >= 32, "Session token too short"
                    # Check it's not a simple pattern
                    assert token != 'admin_token', "Using hardcoded token"
                    
                    # Test token validation
                    response2 = requests.get('http://localhost:8080/profile',
                                           headers={'Authorization': f'Bearer {token}'},
                                           timeout=2)
                    # Should either succeed or give appropriate error
                    assert response2.status_code in [200, 401, 403]
    
    finally:
        proc.terminate()
        proc.wait()

def test_input_validation():
    """Test that input validation prevents malicious inputs."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Test various malicious inputs
        malicious_inputs = [
            {"username": "<script>alert('xss')</script>", "password": "pass"},
            {"username": "verylongusername" * 100, "password": "pass"},
            {"username": "", "password": ""},  # Empty values
            {"username": "admin", "password": "x" * 1000},  # Very long password
        ]
        
        for data in malicious_inputs:
            response = requests.post('http://localhost:8080/login',
                                   json=data,
                                   timeout=2)
            
            # Should handle gracefully - not crash
            assert response.status_code in [200, 400, 401]
            
            # Check no script tags in response
            if response.headers.get('content-type', '').startswith('text/html'):
                assert '<script>' not in response.text, "XSS vulnerability detected"
    
    finally:
        proc.terminate()
        proc.wait()

def test_error_handling():
    """Test that errors don't leak sensitive information."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Test with invalid JSON
        response = requests.post('http://localhost:8080/login',
                               data="not json at all",
                               headers={'Content-Type': 'application/json'},
                               timeout=2)
        
        # Should not crash or show stack trace
        assert response.status_code in [400, 500]
        if response.status_code == 500:
            # Should not show internal details
            content = response.text.lower()
            sensitive_terms = ['traceback', 'file "', 'line ', 'exception:']
            for term in sensitive_terms:
                assert term not in content, f"Error response leaks {term}"
    
    finally:
        proc.terminate()
        proc.wait()

def test_rate_limiting():
    """Test that rate limiting prevents brute force attacks."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Make multiple rapid login attempts
        responses = []
        for i in range(10):
            response = requests.post('http://localhost:8080/login',
                                   json={'username': f'attempt{i}', 'password': 'wrong'},
                                   timeout=1)
            responses.append(response.status_code)
            time.sleep(0.1)  # Small delay
        
        # Should see some rate limiting (429 or failed attempts)
        # Note: Different implementations may handle this differently
        has_429 = any(r == 429 for r in responses)
        has_401 = any(r == 401 for r in responses)
        
        # Either rate limiting or all failures is acceptable
        assert has_429 or (responses.count(401) >= 5), "No rate limiting detected"
    
    finally:
        proc.terminate()
        proc.wait()

def test_functionality_maintained():
    """Test that the fixed app still works correctly."""
    proc = start_app('/app/fixed_auth.py')
    assert proc is not None, "Failed to start fixed application"
    
    try:
        time.sleep(1)
        
        # Clean up any existing test user
        db_path = '/app/users.db'
        if os.path.exists(db_path):
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("DELETE FROM users WHERE username LIKE 'testfunc%'")
            conn.commit()
            conn.close()
        
        # Test registration
        username = f"testfunc_{secrets.token_hex(4)}"
        password = "TestPass123!"
        
        response = requests.post('http://localhost:8080/register',
                               json={'username': username, 'password': password},
                               timeout=2)
        
        # Registration should work
        assert response.status_code == 200, f"Registration failed: {response.status_code}"
        reg_data = response.json()
        
        # Test login with correct credentials
        response = requests.post('http://localhost:8080/login',
                               json={'username': username, 'password': password},
                               timeout=2)
        
        assert response.status_code == 200, f"Login failed: {response.status_code}"
        login_data = response.json()
        
        # Should get a token on successful login
        if login_data.get('success'):
            token = login_data.get('token')
            assert token, "No token returned on successful login"
            
            # Test protected endpoint with token
            response = requests.get('http://localhost:8080/profile',
                                  headers={'Authorization': f'Bearer {token}'},
                                  timeout=2)
            
            assert response.status_code == 200, f"Profile access failed: {response.status_code}"
        
        # Test logout
        response = requests.post('http://localhost:8080/logout',
                               headers={'Authorization': f'Bearer {token}'} if 'token' in locals() else {},
                               timeout=2)
        
        assert response.status_code in [200, 401], f"Logout failed: {response.status_code}"
    
    finally:
        proc.terminate()
        proc.wait()
#!/usr/bin/env python3
"""
Test client for the authentication system.
Use this to test for vulnerabilities and verify fixes.
"""

import requests
import json
import sys
import argparse
import time

BASE_URL = 'http://localhost:8080'

def test_vulnerabilities():
    """Test the vulnerable application for security issues."""
    print("=== Testing Vulnerabilities ===")
    
    # Test 1: SQL Injection
    print("\n1. Testing SQL Injection...")
    test_cases = [
        ("admin' OR '1'='1", "anything"),
        ("testuser", "' OR '1'='1"),
        ("' UNION SELECT 1,'admin','admin' --", "x"),
    ]
    
    for username, password in test_cases:
        try:
            response = requests.post(f'{BASE_URL}/login',
                                   json={'username': username, 'password': password},
                                   timeout=2)
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    print(f"  ✓ SQL Injection SUCCEEDED with: {username}:{password}")
                    print(f"    Token: {data.get('token')}")
                else:
                    print(f"  ✗ Injection blocked: {username}")
            else:
                print(f"  ✗ Request failed: {response.status_code}")
        except Exception as e:
            print(f"  ✗ Error: {e}")
    
    # Test 2: Weak Password Storage
    print("\n2. Testing Password Security...")
    try:
        # Register a user to see how password is stored
        test_user = f"test_{int(time.time())}"
        test_pass = "MySecretPassword123"
        
        response = requests.post(f'{BASE_URL}/register',
                               json={'username': test_user, 'password': test_pass},
                               timeout=2)
        
        if response.status_code == 200:
            print(f"  ✓ User {test_user} registered")
            
            # Try to login with correct password
            response = requests.post(f'{BASE_URL}/login',
                                   json={'username': test_user, 'password': test_pass},
                                   timeout=2)
            if response.status_code == 200:
                print("  ✓ Login with correct password works")
            
            # Check if we can see all users (information disclosure)
            response = requests.get(f'{BASE_URL}/users', timeout=2)
            if response.status_code == 200:
                data = response.json()
                print(f"  ✓ Information Disclosure: Found {len(data.get('users', []))} users")
        else:
            print(f"  ✗ Registration failed: {response.status_code}")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    # Test 3: Session Security
    print("\n3. Testing Session Security...")
    try:
        # Try to guess admin token
        for i in range(1, 5):
            guess_token = f"user_{i}_token"
            response = requests.get(f'{BASE_URL}/profile',
                                  headers={'Authorization': f'Bearer {guess_token}'},
                                  timeout=2)
            if response.status_code == 200:
                print(f"  ✓ Token guessed: {guess_token}")
                data = response.json()
                print(f"    User: {data.get('username')}")
                break
            else:
                print(f"  ✗ Token {guess_token} invalid")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    # Test 4: XSS Potential
    print("\n4. Testing XSS Potential...")
    try:
        response = requests.get(f'{BASE_URL}/profile?bio=<script>alert(1)</script>',
                              headers={'Authorization': 'Bearer user_1_token'},
                              timeout=2)
        if response.status_code == 200:
            data = response.json()
            bio = data.get('bio', '')
            if '<script>' in bio:
                print("  ✓ XSS payload reflected without encoding")
            else:
                print("  ✗ XSS payload appears to be encoded")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    # Test 5: Error Information Leakage
    print("\n5. Testing Error Handling...")
    try:
        # Send invalid JSON
        response = requests.post(f'{BASE_URL}/login',
                               data="not json at all",
                               headers={'Content-Type': 'application/json'},
                               timeout=2)
        if response.status_code == 500:
            data = response.json()
            if 'traceback' in data:
                print("  ✓ Stack trace leaked in error response")
            else:
                print("  ✗ No stack trace in error")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    print("\n=== Vulnerability Testing Complete ===")

def test_fixes():
    """Test that vulnerabilities are fixed."""
    print("=== Testing Fixes ===")
    
    # Test 1: SQL Injection should fail
    print("\n1. Testing SQL Injection Protection...")
    injection_attempts = [
        ("admin' OR '1'='1", "anything"),
        ("' UNION SELECT 1,2,3 --", "x"),
    ]
    
    all_blocked = True
    for username, password in injection_attempts:
        try:
            response = requests.post(f'{BASE_URL}/login',
                                   json={'username': username, 'password': password},
                                   timeout=2)
            data = response.json()
            if data.get('success'):
                print(f"  ✗ SQL Injection still works: {username}")
                all_blocked = False
            else:
                print(f"  ✓ Injection blocked: {username}")
        except Exception as e:
            print(f"  ✓ Request failed (likely blocked): {e}")
    
    if all_blocked:
        print("  ✓ All SQL injection attempts blocked")
    
    # Test 2: Registration and login work normally
    print("\n2. Testing Normal Functionality...")
    try:
        test_user = f"validuser_{int(time.time())}"
        test_pass = "StrongPass123!"
        
        # Register
        response = requests.post(f'{BASE_URL}/register',
                               json={'username': test_user, 'password': test_pass},
                               timeout=2)
        
        if response.status_code == 200:
            print(f"  ✓ Registration works for {test_user}")
            
            # Login
            response = requests.post(f'{BASE_URL}/login',
                                   json={'username': test_user, 'password': test_pass},
                                   timeout=2)
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    token = data.get('token')
                    print(f"  ✓ Login works, got token")
                    
                    # Access profile
                    response = requests.get(f'{BASE_URL}/profile',
                                          headers={'Authorization': f'Bearer {token}'},
                                          timeout=2)
                    
                    if response.status_code == 200:
                        print("  ✓ Profile access works")
                    else:
                        print(f"  ✗ Profile access failed: {response.status_code}")
                else:
                    print("  ✗ Login failed (credentials wrong)")
            else:
                print(f"  ✗ Login failed: {response.status_code}")
        else:
            print(f"  ✗ Registration failed: {response.status_code}")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    # Test 3: Token guessing should fail
    print("\n3. Testing Session Security...")
    try:
        for i in range(1, 5):
            guess_token = f"user_{i}_token"
            response = requests.get(f'{BASE_URL}/profile',
                                  headers={'Authorization': f'Bearer {guess_token}'},
                                  timeout=2)
            if response.status_code == 200:
                print(f"  ✗ Token guessing still works: {guess_token}")
            else:
                print(f"  ✓ Token guessing blocked: {guess_token}")
    except Exception as e:
        print(f"  ✓ Token validation working: {e}")
    
    print("\n=== Fix Testing Complete ===")

def main():
    parser = argparse.ArgumentParser(description='Test authentication system')
    parser.add_argument('--test-vulnerabilities', action='store_true',
                       help='Test for vulnerabilities')
    parser.add_argument('--test-fixes', action='store_true',
                       help='Test that fixes work')
    
    args = parser.parse_args()
    
    if args.test_vulnerabilities:
        test_vulnerabilities()
    elif args.test_fixes:
        test_fixes()
    else:
        print("Please specify --test-vulnerabilities or --test-fixes")

if __name__ == '__main__':
    main()
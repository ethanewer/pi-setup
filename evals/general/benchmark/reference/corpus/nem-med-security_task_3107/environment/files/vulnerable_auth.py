#!/usr/bin/env python3
"""
VULNERABLE AUTHENTICATION SYSTEM
This application has multiple security vulnerabilities.
DO NOT USE IN PRODUCTION!
"""

import sqlite3
import hashlib
from flask import Flask, request, jsonify, make_response
import json

app = Flask(__name__)
DB_FILE = 'users.db'

def init_db():
    """Initialize the database with a users table."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY,
            username TEXT UNIQUE,
            password TEXT
        )
    ''')
    
    # Add a test user if none exists
    cursor.execute("SELECT COUNT(*) FROM users")
    if cursor.fetchone()[0] == 0:
        # Store password as plain MD5 (INSECURE!)
        test_hash = hashlib.md5(b'testpass').hexdigest()
        cursor.execute("INSERT INTO users (username, password) VALUES (?, ?)",
                      ('testuser', test_hash))
    
    conn.commit()
    conn.close()

init_db()

@app.route('/register', methods=['POST'])
def register():
    """Register a new user (INSECURE IMPLEMENTATION)."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    
    username = data.get('username', '').strip()
    password = data.get('password', '')
    
    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400
    
    # Store password as MD5 without salt (INSECURE!)
    password_hash = hashlib.md5(password.encode()).hexdigest()
    
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()
        # SQL INJECTION VULNERABILITY!
        cursor.execute(f"INSERT INTO users (username, password) VALUES ('{username}', '{password_hash}')")
        conn.commit()
        conn.close()
        
        return jsonify({'success': True, 'message': 'User registered'})
    except sqlite3.IntegrityError:
        return jsonify({'error': 'Username already exists'}), 400
    except Exception as e:
        # INFORMATION LEAKAGE: Exposing detailed error
        return jsonify({'error': f'Database error: {str(e)}'}), 500

@app.route('/login', methods=['POST'])
def login():
    """Authenticate a user (INSECURE IMPLEMENTATION)."""
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    
    username = data.get('username', '')
    password = data.get('password', '')
    
    # WEAK PASSWORD HASHING: MD5 without salt
    password_hash = hashlib.md5(password.encode()).hexdigest()
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    
    # SQL INJECTION VULNERABILITY!
    query = f"SELECT id, username FROM users WHERE username = '{username}' AND password = '{password_hash}'"
    cursor.execute(query)
    user = cursor.fetchone()
    conn.close()
    
    if user:
        # INSECURE SESSION TOKEN: Simple pattern
        user_id = user[0]
        token = f"user_{user_id}_token"
        
        response = make_response(jsonify({
            'success': True,
            'message': 'Login successful',
            'token': token,
            'user': {
                'id': user_id,
                'username': user[1]
            }
        }))
        
        # Set cookie with token (INSECURE: No HttpOnly, Secure flags)
        response.set_cookie('session_token', token)
        return response
    else:
        return jsonify({'success': False, 'error': 'Invalid credentials'}), 401

@app.route('/profile', methods=['GET'])
def get_profile():
    """Get user profile (INSECURE IMPLEMENTATION)."""
    # WEAK TOKEN VALIDATION
    token = request.headers.get('Authorization', '').replace('Bearer ', '')
    if not token:
        token = request.cookies.get('session_token', '')
    
    if not token:
        return jsonify({'error': 'Unauthorized'}), 401
    
    # SIMPLE TOKEN PATTERN: Easy to guess
    if token.startswith('user_') and token.endswith('_token'):
        try:
            user_id = int(token.split('_')[1])
            
            conn = sqlite3.connect(DB_FILE)
            cursor = conn.cursor()
            # SQL INJECTION VULNERABILITY!
            cursor.execute(f"SELECT id, username FROM users WHERE id = {user_id}")
            user = cursor.fetchone()
            conn.close()
            
            if user:
                # XSS VULNERABILITY: No output encoding
                return jsonify({
                    'id': user[0],
                    'username': user[1],
                    'bio': request.args.get('bio', 'No bio provided')
                })
        except:
            pass
    
    return jsonify({'error': 'Invalid token'}), 401

@app.route('/users', methods=['GET'])
def list_users():
    """List all users (INSECURE - INFORMATION DISCLOSURE)."""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT id, username FROM users")
    users = cursor.fetchall()
    conn.close()
    
    # INFORMATION DISCLOSURE: Exposing all users
    return jsonify({'users': [{'id': u[0], 'username': u[1]} for u in users]})

@app.route('/logout', methods=['POST'])
def logout():
    """Logout user (INSECURE IMPLEMENTATION)."""
    response = make_response(jsonify({'success': True, 'message': 'Logged out'}))
    # INSECURE: Just removing cookie, no token invalidation
    response.set_cookie('session_token', '', expires=0)
    return response

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(500)
def server_error(error):
    # INFORMATION LEAKAGE: Exposing stack trace
    import traceback
    return jsonify({
        'error': 'Internal server error',
        'details': str(error),
        'traceback': traceback.format_exc()
    }), 500

if __name__ == '__main__':
    print("WARNING: This application has multiple security vulnerabilities!")
    print("Do not use in production!")
    print("Starting server on http://localhost:8080")
    app.run(host='0.0.0.0', port=8080, debug=True)  # DEBUG MODE ENABLED!
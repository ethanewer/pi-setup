from flask import Flask, request, jsonify
import sqlite3
import os

app = Flask(__name__)

# Initialize database
def init_db():
    conn = sqlite3.connect('test.db')
    c = conn.cursor()
    
    # Create users table
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (id INTEGER PRIMARY KEY, username TEXT, password TEXT, email TEXT, notes TEXT, is_admin INTEGER)''')
    
    # Create products table  
    c.execute('''CREATE TABLE IF NOT EXISTS products
                 (id INTEGER PRIMARY KEY, name TEXT, price REAL, description TEXT)''')
    
    # Insert test data
    c.execute("INSERT OR IGNORE INTO users VALUES (1, 'user1', 'password123', 'user1@example.com', 'Sensitive note: FLAG{S3cr3t-Us3r-D4t4}', 0)")
    c.execute("INSERT OR IGNORE INTO users VALUES (2, 'admin', 'admin123', 'admin@example.com', 'Admin notes: FLAG{Adm1n-P0w3r}', 1)")
    c.execute("INSERT OR IGNORE INTO users VALUES (3, 'user2', 'pass456', 'user2@test.com', 'Personal data here', 0)")
    
    c.execute("INSERT OR IGNORE INTO products VALUES (1, 'Laptop', 999.99, 'High-performance laptop')")
    c.execute("INSERT OR IGNORE INTO products VALUES (2, 'Phone', 699.99, 'Smartphone with great camera')")
    c.execute("INSERT OR IGNORE INTO products VALUES (3, 'Tablet', 399.99, 'Portable tablet device')")
    
    conn.commit()
    conn.close()

@app.route('/login', methods=['POST'])
def login():
    """Vulnerable login endpoint - SQL injection"""
    data = request.json
    username = data.get('username', '')
    password = data.get('password', '')
    
    conn = sqlite3.connect('test.db')
    c = conn.cursor()
    
    # SQL Injection vulnerability - concatenating user input directly
    query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
    c.execute(query)
    
    user = c.fetchone()
    conn.close()
    
    if user:
        return jsonify({"message": "Login successful", "user_id": user[0]})
    return jsonify({"error": "Invalid credentials"}), 401

@app.route('/search', methods=['GET'])
def search_products():
    """Vulnerable search endpoint - XSS and SQL injection"""
    search_term = request.args.get('q', '')
    
    conn = sqlite3.connect('test.db')
    c = conn.cursor()
    
    # SQL Injection vulnerability
    query = f"SELECT * FROM products WHERE name LIKE '%{search_term}%' OR description LIKE '%{search_term}%'"
    c.execute(query)
    
    products = c.fetchall()
    conn.close()
    
    # XSS vulnerability - returning raw user input
    results = []
    for product in products:
        results.append({
            "id": product[0],
            "name": product[1],
            "price": product[2],
            "description": product[3],
            "search_term_used": search_term  # Reflected XSS here
        })
    
    return jsonify(results)

@app.route('/profile/<user_id>', methods=['GET'])
def get_profile(user_id):
    """Vulnerable profile endpoint - Insecure Direct Object Reference (IDOR)"""
    conn = sqlite3.connect('test.db')
    c = conn.cursor()
    
    # IDOR vulnerability - no authorization check
    c.execute(f"SELECT id, username, email, notes FROM users WHERE id={user_id}")
    user = c.fetchone()
    conn.close()
    
    if user:
        return jsonify({
            "id": user[0],
            "username": user[1],
            "email": user[2],
            "notes": user[3]  # Exposing sensitive notes without permission check
        })
    return jsonify({"error": "User not found"}), 404

@app.route('/add_note', methods=['POST'])
def add_note():
    """Vulnerable endpoint - missing input validation"""
    data = request.json
    user_id = data.get('user_id')
    note = data.get('note', '')
    
    conn = sqlite3.connect('test.db')
    c = conn.cursor()
    
    # Missing validation - note could be malicious
    c.execute(f"UPDATE users SET notes='{note}' WHERE id={user_id}")
    conn.commit()
    
    # XSS in stored data
    c.execute(f"SELECT notes FROM users WHERE id={user_id}")
    updated_note = c.fetchone()[0]
    conn.close()
    
    return jsonify({"message": "Note updated", "note": updated_note})

if __name__ == '__main__':
    init_db()
    print("Starting vulnerable API on http://localhost:8080")
    print("Database initialized with test data")
    print("WARNING: This API contains multiple security vulnerabilities!")
    app.run(host='0.0.0.0', port=8080, debug=False)
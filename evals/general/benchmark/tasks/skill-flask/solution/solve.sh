#!/bin/bash
set -euo pipefail

cat > /app/app.py <<'EOF'
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route("/")
def index():
    return jsonify({"status": "ok"})

@app.route("/api/greet")
def greet():
    name = request.args.get("name", "world")
    return jsonify({"message": f"Hello, {name}!"})

if __name__ == "__main__":
    app.run()
EOF
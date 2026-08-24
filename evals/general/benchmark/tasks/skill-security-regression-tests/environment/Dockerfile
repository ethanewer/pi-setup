FROM bench-base:python-3.12

RUN pip install --no-cache-dir flask pytest

WORKDIR /app

RUN cat > /app/webapp.py <<'EOF'
from flask import Flask, request

app = Flask(__name__)

@app.route("/greet")
def greet():
    name = request.args.get("name", "world")
    return f"<html><body><h1>Hello {name}!</h1></body></html>"
EOF

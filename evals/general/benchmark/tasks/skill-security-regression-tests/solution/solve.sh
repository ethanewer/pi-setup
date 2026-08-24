#!/bin/bash
set -euo pipefail

cat > /app/test_xss_regression.py <<'EOF'
import sys
sys.path.insert(0, "/app")
from webapp import app


def test_greet_escapes_script_tag():
    client = app.test_client()
    resp = client.get("/greet?name=<script>alert(1)</script>")
    body = resp.get_data(as_text=True)
    assert "<script>alert(1)</script>" not in body
    assert "&lt;script&gt;" in body
EOF

python3 - <<'EOF'
import re
src = open("/app/webapp.py").read()
src = src.replace(
    "from flask import Flask, request",
    "from flask import Flask, request\nfrom markupsafe import escape",
)
src = src.replace(
    'return f"<html><body><h1>Hello {name}!</h1></body></html>"',
    'return f"<html><body><h1>Hello {escape(name)}!</h1></body></html>"',
)
open("/app/webapp.py", "w").write(src)
EOF

python3 -m pytest /app/test_xss_regression.py -q

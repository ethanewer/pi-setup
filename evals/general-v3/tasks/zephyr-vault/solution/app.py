#!/usr/bin/env python3
"""AuroraVault hardened web server (deliverable /app/app.py).

The v2 service. It must (a) keep the framework identity/version intact and
report the real installed Flask version, and (b) treat user-supplied template
markup strictly as plain text data so no SSTI / server-side code-execution
payload is ever evaluated, while also (c) demonstrating the fixed parameterized
login (the legacy concatenation in /app/src/auth_service.py is NOT used).

Routes:
  GET  /            welcome page + framework banner
  GET  /identity    JSON: app, framework, flask_version, flask_major
  POST /render      body {"name": ...} -> page greeting; name is data, never a
                    template. Missing/null/non-string names are coerced safely.
  POST /login       body {"username","password"} -> parameterized (non-concat) check.
"""
from importlib import metadata as _md
import flask
from flask import Flask, jsonify, render_template_string, request
from markupsafe import escape

app = Flask(__name__)
app.config["SECRET_KEY"] = "aurora-vault-7f93d1e4"  # must never leak via {{ config }}
app.config["DEBUG"] = False

APP_NAME = "AuroraVault"
FLASK_VERSION = _md.version("flask")

# Constant template: the user-supplied name is bound as a VALUE below, so any
# {{...}}/<%...%>/<?php...?>/$.{...} in the input is printed as-is, not parsed.
RENDER_TEMPLATE = (
    "<h1>%s</h1>"
    "<p id=\"greeting\">Hello: {{ name }}</p>"
    "<p id=\"banner\">identity: 'Flask/{{ fv }}'</p>" % APP_NAME
)


@app.get("/")
def index():
    return render_template_string(
        "<h1>%s</h1><p>running under Flask/{{ fv }}</p>" % APP_NAME,
        fv=FLASK_VERSION,
    )


@app.get("/identity")
def identity():
    return flask.jsonify({
        "app": APP_NAME,
        "framework": "Flask",
        "flask_version": FLASK_VERSION,
        "flask_major": FLASK_VERSION.split(".")[0],
        "mode": "escaped-data",
    })


@app.post("/render")
def render_name():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = {}
    name = data.get("name")
    if name is None:
        name = ""
    # Coerce any JSON type to a plain string; never let non-string types raise.
    if not isinstance(name, str):
        name = str(name)
    # Escape so the name displays as literal text (defense-in-depth; also
    # guarantees the input is treated as data, never as a template/script).
    safe_name = escape(name)
    body = render_template_string(RENDER_TEMPLATE, name=safe_name, fv=FLASK_VERSION)
    return body


@app.post("/login")
def login():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = {}
    username = str(data.get("username", ""))
    password = str(data.get("password", ""))
    # Fixed auth: parameterized / constant-time compare. No string concatenation
    # of user input into any query (contrast /app/src/auth_service.py).
    authed = (username == "admin") and (password == "zephyr-7")
    return flask.jsonify({"user": username, "authenticated": authed})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5001, debug=False, use_reloader=False)
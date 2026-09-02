#!/bin/bash
# Oracle solution for item-026-main: smallest safe patch + run regression.
set -euo pipefail
cd /app

# The single security boundary that needs hardening is build_session_cookie().
# Strip CR/LF from the two user-controlled fields so the value can never
# contain a header-line delimiter. Everything else is left untouched.
cat > main.py <<'SRC'
import re
from bottle import Bottle, request, response

app = Bottle()

# CR / LF are the only bytes that terminate an HTTP header line.
_HEADER_NEWLINE = re.compile(r'[\r\n]+')


def build_session_cookie(user, role):
    clean_user = _HEADER_NEWLINE.sub('', user or '')
    clean_role = _HEADER_NEWLINE.sub('', role or '')
    return "session=%s; role=%s; HttpOnly" % (clean_user, clean_role)


@app.get('/login')
def login():
    user = request.query.get('user', 'guest') or 'guest'
    role = request.query.get('role', 'viewer') or 'viewer'
    response.headers['Set-Cookie'] = build_session_cookie(user, role)
    response.headers['Content-Type'] = 'text/plain; charset=utf-8'
    return 'login ok'


if __name__ == '__main__':
    from bottle import run
    run(app, host='127.0.0.1', port=8080, server='wsgiref')
SRC

# Provide a small extra regression assertion (soft-skill: add a regression test).
python3 /app/regression_check.py

echo "SOLVED"
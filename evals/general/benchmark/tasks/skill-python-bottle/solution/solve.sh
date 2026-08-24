#!/bin/bash
set -euo pipefail
cat > /app/bottle_app.py <<'PY'
from bottle import route, run, request, response

@route("/session")
def session():
    try:
        c = int(request.get_cookie("count"))
    except (TypeError, ValueError):
        c = 0
    c += 1
    response.set_cookie("count", str(c))
    return str(c)

run(host="127.0.0.1", port=8080)
PY
python3 -c "import py_compile; py_compile.compile('/app/bottle_app.py', doraise=True)"
echo "bottle_app.py written and compiles"

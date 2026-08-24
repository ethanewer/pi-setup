FROM bench-base:python-3.12

WORKDIR /app

RUN python3 - <<'PYEOF'
import json
code = r'''
import json, sys

def load():
    try:
        with open('/app/settings.json') as f:
            cfg = json.load(f)
    except Exception as e:
        print("ERROR: cannot load settings.json: %s" % e)
        return
    req = ("host", "port", "workers")
    # validate required keys and types
    for k in req:
        if k not in cfg:
            print("ERROR: missing key %s" % k)
            return
    if not isinstance(cfg["host"], str) or not cfg["host"]:
        print("ERROR: host must be a non-empty string")
        return
    if not isinstance(cfg["port"], int) or not (1024 <= cfg["port"] <= 65535):
        print("ERROR: port must be an int in [1024,65535]")
        return
    if not isinstance(cfg["workers"], int) or not (1 <= cfg["workers"] <= 16):
        print("ERROR: workers must be an int in [1,16]")
        return
    print("STARTED")

load()
'''
open('/app/server_app.py', 'w').write(code)
PYEOF
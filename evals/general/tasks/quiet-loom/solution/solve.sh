#!/bin/bash
# Oracle for quiet-loom: write the deliverable Jupyter config file.
# Never reads /tests.
set -eu

CFG="/app/jupyter_notebook_config.py"

cat > "$CFG" <<'PY'
"""Quiet Loom analytics pod Jupyter Server configuration.

Reads the deployment profile for the listen port; binds the wildcard
interface with authentication disabled for the internal probe service.
"""
import json
import os

c = get_config()  # noqa: F821  (provided by the Jupyter config loader)

DEFAULT_PORT = 9318
PROFILE_PATH = "/app/deploy_profile.json"


def _profile_port():
    try:
        with open(PROFILE_PATH, "r", encoding="utf-8") as fh:
            profile = json.load(fh)
    except Exception:
        return DEFAULT_PORT
    if not isinstance(profile, dict):
        return DEFAULT_PORT
    port = profile.get("listen_port")
    if isinstance(port, bool) or not isinstance(port, int):
        return DEFAULT_PORT
    if not (1 <= port <= 65535):
        return DEFAULT_PORT
    return port


_port = _profile_port()

# --- binding: wildcard interface, profile-derived port -----------------------
c.ServerApp.ip = "0.0.0.0"
c.NotebookApp.ip = "0.0.0.0"
c.ServerApp.port = _port
c.NotebookApp.port = _port

# --- authentication fully disabled (probed) ----------------------------------
c.ServerApp.token = ""
c.ServerApp.password = ""
c.NotebookApp.token = ""
c.NotebookApp.password = ""

# --- headless / root ----------------------------------------------------------
c.ServerApp.open_browser = False
c.NotebookApp.open_browser = False
c.ServerApp.allow_root = True
PY

chmod 644 "$CFG"
echo "solve.sh done -> $CFG"
ls -l "$CFG"

#!/bin/bash
# Oracle for elm-ridge: author the real provisioning script and run it to build
# the reproducible workspace and write the lock file. Never reads /tests.
set -euo pipefail

LOCAL=/opt/ridge-index
PY=python3

cat > /app/provision.sh <<'PROV'
#!/bin/bash
# Ridgeline reproducible workspace provisioner. Idempotent: safe to run from any
# pre-existing /app/venvs state (absent / partial / stale / corrupt) because each
# venv is (re)created with --clear, then the pinned packages are installed and the
# gRPC bindings are generated.
set -euo pipefail

BASE=/app
LOCAL=/opt/ridge-index
PY=python3

mkdir -p "$BASE/venvs"

# --- analytics venv ---------------------------------------------------------
"$PY" -m venv --system-site-packages --clear "$BASE/venvs/analytics"
A="$BASE/venvs/analytics/bin/python"
"$A" -m pip install --quiet --no-index --find-links="$LOCAL" \
    'ridgekit==3.1.4' 'ridgemath==0.9.2' 'sidereal==0.2.1' 'ridgedf==2.1.0'

# --- server venv ------------------------------------------------------------
"$PY" -m venv --system-site-packages --clear "$BASE/venvs/server"
S="$BASE/venvs/server/bin/python"
"$S" -m pip install --quiet --no-index --find-links="$LOCAL" 'chain_query==1.0.0'

# --- gRPC bindings generated from /app/chain.proto into server site-packages --
SITE="$("$S" -c 'import site; print(site.getsitepackages()[0])')"
"$S" -m grpc_tools.protoc -I "$BASE" \
    --python_out="$SITE" --grpc_python_out="$SITE" "$BASE/chain.proto"

# --- Jupyter notebook config ------------------------------------------------
cat > "$BASE/jupyter_config.py" <<'JUP'
c.ServerApp.port = 8899
c.ServerApp.ip = "127.0.0.1"
c.ServerApp.open_browser = False
c.ServerApp.token = "ridge"
c.ServerApp.allow_root = True
JUP

# --- lock file: pip freeze of the analytics environment ---------------------
"$BASE/venvs/analytics/bin/pip" freeze > "$BASE/requirements.lock"

echo "provisioning complete"
PROV

chmod +x /app/provision.sh

# Run the provisioner to build the workspace and write /app/requirements.lock.
bash /app/provision.sh

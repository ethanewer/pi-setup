#!/bin/bash
# Oracle for gale-fathom: author the real, idempotent /app/provision.sh deliverable
# and RUN it to actually build the whole Gale Fathom platform. Never reads /tests.
set -euo pipefail

cat > /app/provision.sh <<'PROV_EOF'
#!/bin/bash
# Gale Fathom platform provisioner. Idempotent: safe to run from any
# pre-existing /app state (fresh / stale venv / wrong-version conda env /
# missing services / missing uv project / missing shell init).
set -euo pipefail

BASE=/app
INDEX=/opt/gale-index
INSTALLER=/opt/miniconda-installer.sh
HOST_WEB_ROOT=/var/www/fathom

echo "== provisioning Gale Fathom platform =="

# ---- 1. Non-interactive web + SSH stack (git ships preinstalled) ----------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 || true
dpkg -s nginx >/dev/null 2>&1 || apt-get install -y -qq --no-install-recommends nginx >/dev/null
dpkg -s openssh-server >/dev/null 2>&1 || apt-get install -y -qq --no-install-recommends openssh-server >/dev/null
[ -f /etc/ssh/ssh_host_rsa_key ] || ssh-keygen -A >/dev/null 2>&1 || true

# ---- 2. Pinned Miniconda install + conda env gale311 (python 3.11) -------
CONDA_BIN=/app/miniconda3/bin/conda
if [ ! -x "$CONDA_BIN" ]; then
    bash "$INSTALLER" -bfp /app/miniconda3
    "$CONDA_BIN" config --system --set auto_update_conda false
fi
env_pyver() { "$CONDA_BIN" run -n gale311 python -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo none; }
if "$CONDA_BIN" env list | awk '{print $1}' | grep -q '^gale311$' && [ "$(env_pyver)" = "3.11" ]; then
    : # ok
else
    "$CONDA_BIN" env remove -y -n gale311 >/dev/null 2>&1 || true
    "$CONDA_BIN" create -q -y -n gale311 python=3.11
fi
"$CONDA_BIN" run -n gale311 pip install -q --no-index --find-links="$INDEX" 'fathom_core==2.4.0'

# ---- 3. Python venv at /app/env/.venv with pinned fathom_core --------------
mkdir -p "$BASE/env"
python3 -m venv --clear "$BASE/env/.venv"
"$BASE/env/.venv/bin/pip" install -q --no-index --find-links="$INDEX" 'fathom_core==2.4.0'

# ---- 4. Self-contained uv project at /app/fathom ---------------------------
mkdir -p "$BASE/fathom"
cat > "$BASE/fathom/pyproject.toml" <<'PYPRJ'
[project]
name = "fathom-tools"
version = "1.4.0"
requires-python = ">=3.11"
dependencies = ["fathom_core==2.4.0", "gale_math==0.6.1"]

[tool.uv]
find-links = ["/opt/gale-index"]
PYPRJ
cd "$BASE/fathom"
uv sync >/dev/null

# ---- 5. Login-shell init files (bash + zsh) activate conda + gale311 -------
CONDA_PROFILE="$BASE/miniconda3/etc/profile.d/conda.sh"
for rc in /root/.bashrc /root/.zshrc; do
    touch "$rc"
    if ! grep -qF 'conda activate gale311' "$rc"; then
        printf '\n# Gale Fathom activation\nsource %s\nconda activate gale311\n' "$CONDA_PROFILE" >> "$rc"
    fi
done

# ---- 6. Web marker served by nginx on 127.0.0.1:8091 -----------------------
mkdir -p "$HOST_WEB_ROOT"
printf 'gale-fathom online\n' > "$HOST_WEB_ROOT/marker.html"
cat > "$BASE/nginx-fathom.conf" <<'NGX'
worker_processes 1;
daemon on;
pid /app/nginx.pid;
error_log /app/nginx-error.log;
events { worker_connections 64; }
http {
    access_log off;
    server {
        listen 127.0.0.1:8091;
        root /var/www/fathom;
        index marker.html;
    }
}
NGX
( [ ! -f /app/nginx.pid ] || [ ! -d /proc/"$(cat /app/nginx.pid)" ] ) \
    && /usr/sbin/nginx -c "$BASE/nginx-fathom.conf" || true

# ---- 7. Pinned lock file -----------------------------------------------------
"$BASE/env/.venv/bin/pip" freeze > "$BASE/pinned.txt"

echo "== provisioning complete =="
PROV_EOF

chmod +x /app/provision.sh

# Run the provisioner to build the platform and produce /app/pinned.txt.
bash /app/provision.sh

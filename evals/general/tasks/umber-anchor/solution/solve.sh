#!/usr/bin/env bash
# Oracle for umber-anchor: creates every /app deliverable by doing the real work.
set -euo pipefail

# --- Deliverable 4: the generalized version-constraint checker tool. ---------
cp /solution/confirm_versions.py /app/confirm_versions.py
chmod +x /app/confirm_versions.py

# --- Deliverable 1: author the dependency manifest (numpy/pandas +
#     a plotting + a scientific library), all with pinned-version operators.
cat > /app/requirements.txt <<'EOF'
# umber analysis dev manifest
numpy==1.26.4
pandas==2.2.2
scipy==1.13.1
matplotlib==3.9.1
EOF

# --- Deliverable 2: resolve the pairwise conflict in /app/environment.lock.
# numpy 2.5.0 is incompatible with the solver library's requirement numpy<2.3,
# so re-pin the base numeric library to a version scipy 1.12.0 accepts.
python3 - <<'PY'
p = '/app/environment.lock'
s = open(p).read()
assert 'numpy==2.5.0' in s, 'environment.lock did not start with the expected broken pair'
s = s.replace('numpy==2.5.0', 'numpy==1.26.4')
open(p, 'w').write(s)
print('fixed /app/environment.lock')
PY

# --- Deliverable 3: user rc wiring the framework theme + exact plugin set.
cat > /app/.zshrc <<'EOF'
# umber-anchor zsh config
export ZSH_THEME="midnight"
plugins=(github history-substring-search zsh-autosuggestions)
source /app/zframe/load.zsh
EOF

# Report what was produced.
ls -la /app/requirements.txt /app/environment.lock /app/confirm_versions.py /app/.zshrc
echo "oracle complete"
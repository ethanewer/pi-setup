#!/usr/bin/env bash
# Verifier for umber-anchor. Executes every /app deliverable for real:
#   pip-installs the two manifests into isolated venvs (asserts the dependency
#   conflict was actually resolved), runs /app/confirm_versions.py on both
#   manifests and on hidden inputs, and sources /app/.zshrc in a fresh zsh to
#   confirm the named theme and the exact plugin set are active.
set -uo pipefail
mkdir -p /logs/verifier

reward=1
say(){ echo "[umber-anchor] $*"; }

# ---------------------------------------------------------------------------
# Part A: Dependency manifest (requirements.txt) must resolve and hold its pins.
# ---------------------------------------------------------------------------
python3 -m venv /opt/vrq 2>/dev/null
if ! /opt/vrq/bin/pip install --no-cache-dir -q -r /app/requirements.txt >/tmp/rq.log 2>&1; then
    say "FAIL: /app/requirements.txt did not resolve+install"; reward=0
else
    if ! /opt/vrq/bin/python /app/confirm_versions.py /app/requirements.txt >/tmp/rqc.log 2>&1; then
        say "FAIL: pinned constraints in/on requirements.txt not honored by installed set"
    else
        say "OK requirements.txt installs and pins hold"
        reward=1
    fi
fi

# ---------------------------------------------------------------------------
# Part B: environment.lock must be conflict-free (resolver builds a consistent # set).
# ---------------------------------------------------------------------------
site_b=0
python3 -m venv /opt/venv 2>/dev/null
if /opt/venv/bin/pip install --no-cache-dir -q -r /app/environment.lock >/tmp/env.log 2>&1; then
    if /opt/venv/bin/python /app/confirm_versions.py /app/environment.lock >/tmp/envc.log 2>&1; then
        say "PASS: environment.lock resolves and pins hold"
        site_b=1
    else
        say "FAIL: environment.lock pins not honored"
    fi
else
    say "FAIL: /app/environment.lock still has a resolver conflict"
fi

# ---------------------------------------------------------------------------
# Part C: zsh framework — named theme + exact plugin set active in a fresh zsh.
# ---------------------------------------------------------------------------
site_c=0
theme=$(zsh -f -c 'source /app/.zshrc >/dev/null 2>&1; print -r -- "$THEME_STATUS"' 2>/dev/null)
plugs=$(zsh -f -c 'source /app/.zshrc >/dev/null 2>&1; print -r -- "$PLUGIN_STATUS"' 2>/dev/null)
if [[ "$theme" == "active:midnight" && "$plugs" == "github,history-substring-search,zsh-autosuggestions" ]]; then
    say "PASS: zsh theme=$theme plugins=$plugs (both expected)"
    site_c=1
else
    say "FAIL: zsh activation mismatch  theme='${theme}' plugins='${plugs}'"
fi

# ---------------------------------------------------------------------------
# Part D: hidden confirm_versions cases (executes-deliverable generalization).
# ---------------------------------------------------------------------------
site_d=1
python3 -m venv /opt/hv 2>/dev/null
if ! /opt/hv/bin/pip install --no-cache-dir -q numpy==1.26.4 scipy==1.12.0 requests==2.32.3 >/tmp/hv.log 2>&1; then
    say "FAIL: could not prepare hidden reference env"; site_d=0
fi

run_case(){
    local f=$1 want=$2
    /opt/hv/bin/python /app/confirm_versions.py "$f" >/tmp/hcase.log 2>&1
    local got=$?
    if [[ "$got" != "$want" ]]; then
        say "FAIL hidden manifest $(basename "$f") expected rc=$want got=$got"
        cat /tmp/hcase.log
        site_d=0
    else
        say "PASS hidden $(basename "$f") (rc=$got as expected)"
    fi
}
run_case /tests/hidden/h1_valid_edges.txt        0
run_case /tests/hidden/h2_version_mismatch.txt   1
run_case /tests/hidden/h3_missing_pkg.txt        1
run_case /tests/hidden/h4_only_meta.txt          0

# ---------------------------------------------------------------------------
if [[ "$reward" -eq 1 && "$site_b" -eq 1 && "$site_c" -eq 1 && "$site_d" -eq 1 ]]; then
    reward=1
else
    reward=0
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
#!/usr/bin/env bash
# Verifier for hollow-atlas (git lifecycle repair).
# Executes the deliverables: inspects the git repo branches + recovered work, checks
# the isolated per-branch deployments, checks both sanitized workflow files, re-runs
# the reusable helpers (/app/bin/checkout.py, /app/bin/sanitize.py) on hidden
# fixtures, and proves the SSH-served bare remote is clone-able and push-able.
set -u
mkdir -p /logs/verifier
reward=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail(){ echo "FAIL: $*" >&2; FAILED=1; }

# --- helper: a workflow file must have no token on any NON-comment line ---
is_clean() { # $1 file
  python3 - "$1" <<'PY'
import sys
p = sys.argv[1]
tok = 'nightfall-ops.example'
bad = []
with open(p) as f:
    lines = f.readlines()
for i, ln in enumerate(lines, 1):
    if ln.lstrip().startswith('#'):
        continue
    if tok in ln.lower():
        bad.append((i, ln.rstrip('\n')))
if bad:
    for i, l in bad:
        print('   token on non-comment line %d: %s' % (i, l), file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

FAILED=0

# ============================ 2) branches from bundles ============================
REPO=/app/repo
if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "/app/repo is not a git repository"
else
  for br in feature-aurora feature-marble; do
    if git -C "$REPO" rev-parse --verify --quiet "refs/heads/$br" >/dev/null 2>&1; then
      :
    else
      fail "branch $br missing from /app/repo"
    fi
  done
  # branch tips carry their marker files
  a="$(git -C "$REPO" show 'feature-aurora:src/aura_mapper.py' 2>/dev/null || true)"
  m="$(git -C "$REPO" show 'feature-marble:src/marble_ledger.py' 2>/dev/null || true)"
  case "$a" in *AURORA*) ;; *) fail "feature-aurora tip lacks src/aura_mapper.py";; esac
  case "$m" in *MARBLE*) ;; *) fail "feature-marble tip lacks src/marble_ledger.py";; esac
fi

# --- 2) recovered off-branch work (fallback path inside the verifier) ---
if git -C "$REPO" rev-parse --verify --quiet 'refs/heads/feature-aurora' >/dev/null 2>&1; then
  exp="$(git -C "$REPO" show 'stash@{0}^3:src/recovered_work.py' 2>/dev/null || true)"
  got="$(git -C "$REPO" show 'feature-aurora:src/recovered_work.py' 2>/dev/null || true)"
  if [ -z "$exp" ]; then
    fail "cannot read stash lost-work content"
  elif [ "$exp" != "$got" ]; then
    fail "recovered_work.py on feature-aurora does not match the stashed content"
  else
    # ensure the file really is committed on the branch (in the tree) not just a fuse
    git -C "$REPO" cat-file -e "feature-aurora:src/recovered_work.py" 2>/dev/null || \
      fail "recovered_work.py not committed into feature-aurora tree"
  fi
else
  fail "feature-aurora absent - cannot verify recovery"
fi

# --- 2) isolated per-branch deployments ------------------------------------
da=/app/deploy/aurora/; dm=/app/deploy/marble/
ck(){ # $1 file expected $2 label
  if [ -f "$1" ]; then case "$(cat "$1")" in *"$2"*) ;; *) fail "$3";; esac; else fail "$3"; fi
}
if [ -f "$da/src/aura_mapper.py" ] || [ -d /app/deploy ]; then
  if [ -f "$da/src/aura_mapper.py" ]; then :; else fail "deploy/aurora missing aura_mapper.py"; fi
  if [ -f "$da/src/recovered_work.py" ]; then :; else fail "deploy/aurora missing recovered_work.py"; fi
  if [ -f "$da/src/marble_ledger.py" ]; then fail "deploy/aurora wrongly contains marble_ledger.py"; fi
  if [ -f "$dm/src/marble_ledger.py" ]; then :; else fail "deploy/marble missing marble_ledger.py"; fi
  if [ -f "$dm/src/aura_mapper.py" ]; then fail "deploy/marble wrongly contains aura_mapper.py"; fi
  if [ -f "$dm/src/recovered_work.py" ]; then fail "deploy/marble wrongly contains recovered_work.py"; fi
  case "$(cat "$da/src/aura_mapper.py" 2>/dev/null)" in *AURORA*) ;; *) fail "aurora content not AURORA";; esac
  case "$(cat "$dm/src/marble_ledger.py" 2>/dev/null)" in *MARBLE*) ;; *) fail "marble content not MARBLE";; esac
else
  fail "deployment directories absent"
fi

# --- 3) sanitized workflows ------------------------------------------------
if is_clean /app/ci.yml; then :; else fail "/app/ci.yml still has upload sink on a non-comment line"; fi
if is_clean /app/repo/.github/workflows/deploy.yml; then :; else fail "in-repo deploy.yml still has upload sink"; fi
if grep -qi 'nightfall-ops.example' /app/ci.yml; then
  # token may only survive inside comments - verify every surviving line is a comment
  if python3 - /app/ci.yml <<'PY'
import sys
for ln in open(sys.argv[1]):
    if 'nightfall-ops.example' in ln.lower() and not ln.lstrip().startswith('#'):
        sys.exit(1)
PY
  then :; else fail "/app/ci.yml surviving sink references live on non-comment lines"; fi
fi

# --- 4) reusable helpers present ------------------------------------------
for h in /app/bin/sanitize.py /app/bin/checkout.py; do
  if [ -x "$h" ]; then :; else fail "helper not present/executable: $h"; fi
done

# --- 5) hidden sanitize fixtures -------------------------------------------
for f in /tests/hidden/san_wf_*.yml; do
  [ -f "$f" ] || continue
  bn=$(basename "$f")
  python3 /app/bin/sanitize.py "$f" "$work/san_$bn" || { fail "sanitize.py crashed on $bn"; continue; }
  if is_clean "$work/san_$bn"; then :; else fail "sanitize.py output still dirty for $bn"; fi
  # every comment-only mention must survive (edge case: san_wf_b)
  if [ "$bn" = "san_wf_b.yml" ]; then
    if grep -qi 'nightfall-ops.example' "$work/san_$bn"; then :; else fail "san_wf_b comment mention was dropped"; fi
  fi
done

# --- 6) hidden checkout fixture --------------------------------------------
mkdir -p "$work/hcheck"
mkdir -p "$work/hcheck/repo"
tar -xzf /tests/hidden/checkout/repo.tar.gz -C "$work/hcheck"
cp -r /tests/hidden/checkout/bundles "$work/hcheck/bundles"
if python3 /app/bin/checkout.py "$work/hcheck/bundles" "$work/hcheck/repo" >/dev/null 2>&1; then
  for br in amplus-flume amplus-quill; do
    if git -C "$work/hcheck/repo" rev-parse --verify --quiet "refs/heads/$br" >/dev/null 2>&1; then
      :
    else
      fail "hidden checkout: branch $br not created"
    fi
  done
  git -C "$work/hcheck/repo" show 'amplus-flume:src/flume_marker.py' 2>/dev/null | grep -q FLUME || fail "hidden flume marker content wrong"
  git -C "$work/hcheck/repo" show 'amplus-quill:src/quill_marker.py' 2>/dev/null | grep -q QUILL || fail "hidden quill marker content wrong"
else
  fail "hidden checkout.py failed"
fi

# --- 7) SSH-served bare remote ----------------------------------------------
git config --global --add safe.directory /srv/git/atlas.git 2>/dev/null || true
if id gitops >/dev/null 2>&1; then :; else fail "gitops user missing"; fi
if [ -d /srv/git/atlas.git ] && [ -f /srv/git/atlas.git/HEAD ]; then :; else fail "/srv/git/atlas.git bare repo missing"; fi
if pgrep -x sshd >/dev/null 2>&1; then :; else fail "sshd not running"; fi

if id gitops >/dev/null 2>&1; then
  if [ -f /app/ssh/deploy_key ] && [ -s /app/ssh/deploy_key ]; then
    export GIT_SSH_COMMAND="ssh -i /app/ssh/deploy_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=10"
    if git clone -q gitops@localhost:/srv/git/atlas.git "$work/remote_clone" 2>/dev/null; then
      if [ -f "$work/remote_clone/.git/HEAD" ]; then
        : # clone succeeded
      else
        fail "cloned remote missing HEAD"
      fi
      # push a new branch back
      if (cd "$work/remote_clone" \
          && git config user.email v@h && git config user.name verifier \
          && printf 'probe-%s\n' "$$" > probe_push.txt \
          && git add probe_push.txt && git commit -qm probe \
          && git push -q origin HEAD:refs/heads/probe-push 2>/dev/null); then
        rev=$(git -C /srv/git/atlas.git rev-parse --verify --quiet refs/heads/probe-push 2>/dev/null || true)
        if [ -n "$rev" ]; then :; else fail "remote does not contain pushed branch"; fi
      else
        fail "push to /srv/git/atlas.git failed"
      fi
    else
      fail "SSH clone gitops@localhost:/srv/git/atlas.git failed"
    fi
  else
    fail "deploy key /app/ssh/deploy_key missing or empty"
  fi
fi

# ---------------------------------------------------------------------------
if [ "$FAILED" = 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
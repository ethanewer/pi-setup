#!/bin/bash
# Oracle for "umber-yonder": clone the compromised remote over password SSH,
# expunge both committed secrets from every object, recover the retry
# credential, and record the rewritten history + push/trigger command list.
set -euo pipefail

mkdir -p /run/sshd
if ! pgrep -x sshd >/dev/null 2>&1; then
  /usr/sbin/sshd; sleep 1
fi

export GIT_SSH_COMMAND="sshpass -p eastbank4 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no"

# --- 1. clone the incident repo into /app/repo (password-automated) --------
if [ ! -d /app/repo/.git ]; then
  rm -rf /app/repo
  git clone -q gitdev@127.0.0.1:/srv/git/paloma.git /app/repo
fi
git -C /app/repo config user.email oracle@local
git -C /app/repo config user.name oracle

# --- 2. write the reusable scrubber deliverable -----------------------------
cat > /app/repurge.py <<'PY'
#!/usr/bin/env python3
"""repurge.py - reusable git secret-scrubber for the umber-yonder task.

Usage:  python3 repurge.py <repodir> [out.json]

Operates on a linked working git repository IN PLACE:
  1. discovers every "api key" literal (pattern [A-Z]{2,6}-[A-F0-9]{4}-[A-F0-9]{4})
     anywhere in the object store and working tree,
  2. recovers the single committed-then-deleted "retry credential"
     (pattern [A-Z]{2,5}:[0-9a-f]{8}) that exists in history/dangling objects but
     NOT in the current working tree,
  3. rewrites ALL reachable history (trees, blobs and commit messages) replacing
     those values with fixed per-type placeholders, editing ONLY files that
     contain a secret so every unrelated file stays byte-identical,
  4. drops the original/dangling objects and prunes them so a byte-level scan of
     every object finds no trace of either secret,
  5. self-scans and reports {"ok": bool, "recovered": ...} to stdout + out.json.

For non-repository inputs it exits 0 with {"ok": false} instead of crashing.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

API_RE = re.compile(rb"\b[A-Z]{2,6}-[A-F0-9]{4}-[A-F0-9]{4}\b")
REC_RE = re.compile(rb"\b[A-Z]{2,5}:[0-9a-f]{8}\b")
API_PH = "[REDACTED_API_KEY]"
REC_PH = "[REDACTED_CREDENTIAL]"


def g(repo, *args, input=None):
    return subprocess.run(["git", "-C", repo, *args],
                          capture_output=True, input=input)


def all_objects(repo):
    """Return (type, content) for every (blob/commit) object in the store."""
    out = subprocess.run(["git", "-C", repo, "cat-file", "--batch-all-objects",
                          "--batch"], capture_output=True).stdout
    res = []
    pos = 0
    n = len(out)
    while pos < n:
        nl = out.find(b"\n", pos)
        if nl < 0:
            break
        hdr = out[pos:nl].split()
        if len(hdr) < 3:
            break
        _sha, typ, size = hdr[0], hdr[1], int(hdr[2])
        start = nl + 1
        if typ in (b"blob", b"commit"):
            res.append((typ, out[start:start + size]))
        pos = start + size
        if pos < n and out[pos:pos + 1] == b"\n":
            pos += 1
    return res


def vals_in(data, rx):
    return set(m.group(0) for m in rx.finditer(data))


def worktree_data(repo):
    out = g(repo, "ls-files", "-z").stdout
    for p in out.split(b"\0"):
        if not p:
            continue
        fp = os.path.join(repo, os.fsdecode(p))
        try:
            with open(fp, "rb") as f:
                yield fp, f.read()
        except OSError:
            continue


def _rci(data, pat, repl):
    if pat not in data and pat.lower() not in data.lower():
        return data
    lpat = pat.lower()
    ld = data.lower()
    out = bytearray()
    i = 0
    while True:
        j = ld.find(lpat, i)
        if j < 0:
            out += data[i:]
            break
        out += data[i:j]
        out += repl
        i = j + len(pat)
    return bytes(out)


def discover(repo):
    objs = all_objects(repo)
    api = set()
    rec = set()
    for _typ, data in objs:
        api |= vals_in(data, API_RE)
        rec |= vals_in(data, REC_RE)
    wt_rec = set()
    for _fp, data in worktree_data(repo):
        wt_rec |= vals_in(data, REC_RE)
    recovered = sorted(rec - wt_rec)
    recovered = recovered[0] if recovered else None
    forbid = [[k, "api"] for k in sorted(api)]
    if recovered is not None:
        forbid.append([recovered, "rec"])
    return forbid, recovered


TREE_SCRIPT = r"""
import os, json
fb = json.load(open(os.environ["RP_FORBID"]))
def rci(data, pat, repl):
    if pat not in data and pat.lower() not in data.lower():
        return data
    lpat = pat.lower(); ld = data.lower(); out = bytearray(); i = 0
    while True:
        j = ld.find(lpat, i)
        if j < 0:
            out += data[i:]; break
        out += data[i:j]; out += repl; i = j + len(pat)
    return bytes(out)
for root, dirs, files in os.walk("."):
    if ".git" in dirs: dirs.remove(".git")
    for fn in files:
        p = os.path.join(root, fn)
        try:
            d = open(p, "rb").read()
        except OSError:
            continue
        nd = d
        for item in fb:
            pat = item["k"].encode("latin1")
            if b"\x00" in nd[:8000]:
                continue
            repl = ("[REDACTED_API_KEY]" if item["t"] == "api" else "[REDACTED_CREDENTIAL]").encode()
            nd = rci(nd, pat, repl)
        if nd != d:
            open(p, "wb").write(nd)
"""

MSG_SCRIPT = r"""
import os, sys, json
fb = json.load(open(os.environ["RP_FORBID"]))
def rci(data, pat, repl):
    if pat not in data and pat.lower() not in data.lower():
        return data
    lpat = pat.lower(); ld = data.lower(); out = bytearray(); i = 0
    while True:
        j = ld.find(lpat, i)
        if j < 0:
            out += data[i:]; break
        out += data[i:j]; out += repl; i = j + len(pat)
    return bytes(out)
msg = sys.stdin.buffer.read()
for item in fb:
    pat = item["k"].encode("latin1")
    repl = ("[REDACTED_API_KEY]" if item["t"] == "api" else "[REDACTED_CREDENTIAL]").encode()
    msg = rci(msg, pat, repl)
sys.stdout.buffer.write(msg)
"""


def rewrite(repo, forbid):
    if not forbid:
        return True
    tmp = tempfile.mkdtemp(prefix="repurge_")
    tree_py = os.path.join(tmp, "tree.py")
    msg_py = os.path.join(tmp, "msg.py")
    forbid_json = os.path.join(tmp, "forbid.json")
    with open(tree_py, "w") as f:
        f.write(TREE_SCRIPT)
    with open(msg_py, "w") as f:
        f.write(MSG_SCRIPT)
    with open(forbid_json, "w") as f:
        json.dump([{"k": k.decode("latin1"), "t": t} for k, t in forbid], f)
    env = dict(os.environ)
    env["FILTER_BRANCH_SQUELCH_WARNING"] = "1"
    env["RP_FORBID"] = forbid_json
    r = subprocess.run(
        ["git", "-C", repo, "filter-branch", "--force",
         "--tree-filter", "python3 " + tree_py,
         "--msg-filter", "python3 " + msg_py,
         "--tag-name-filter", "cat", "--", "--all"],
        capture_output=True, env=env)
    if r.returncode != 0:
        sys.stderr.write(r.stdout.decode(errors="replace"))
        sys.stderr.write(r.stderr.decode(errors="replace"))
        return False
    return True


def cleanup(repo):
    out = g(repo, "for-each-ref", "--format=%(refname)", "refs/original").stdout
    for r in out.decode().splitlines():
        if r:
            g(repo, "update-ref", "-d", r)
    out = g(repo, "for-each-ref", "--format=%(refname)", "refs/remotes").stdout
    for r in out.decode().splitlines():
        if r:
            g(repo, "update-ref", "-d", r)
    g(repo, "reflog", "expire", "--expire=now", "--all")
    g(repo, "reset", "--hard")
    g(repo, "gc", "--prune=now")


def self_scan(repo, forbid):
    needles = []
    for k, _t in forbid:
        needles.append(k.lower())
    for _typ, data in all_objects(repo):
        low = data.lower()
        for needle in needles:
            if needle in low:
                return False
    for _fp, data in worktree_data(repo):
        low = data.lower()
        for needle in needles:
            if needle in low:
                return False
    return True


def main():
    if len(sys.argv) < 2:
        return 1
    repo = os.path.abspath(sys.argv[1])
    outjson = sys.argv[2] if len(sys.argv) > 2 else None
    res = {"ok": False}
    if not os.path.isdir(os.path.join(repo, ".git")):
        res["error"] = "not a git repository"
        _write(res, outjson)
        print(json.dumps(res))
        return 0

    forbid, recovered = discover(repo)

    if forbid:
        if not rewrite(repo, forbid):
            res["error"] = "history rewrite failed"
            _write(res, outjson)
            print(json.dumps(res))
            return 0

    cleanup(repo)
    clean = self_scan(repo, forbid) if forbid else True
    head = g(repo, "rev-parse", "HEAD").stdout.decode().strip()

    res = {
        "ok": bool(clean),
        "recovered": recovered.decode() if recovered else None,
        "secrets_removed": len(forbid),
        "head": head,
    }
    _write(res, outjson)
    print(json.dumps(res))
    return 0


def _write(res, outjson):
    if outjson:
        with open(outjson, "w") as f:
            json.dump(res, f)


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/repurge.py

# --- 3. run it (recover + expunge + gc) ------------------------------------
python3 /app/repurge.py /app/repo /app/repurge_out.json
RECOVERED=$(python3 -c 'import json;print(json.load(open("/app/repurge_out.json")).get("recovered") or "")')

# --- 4. record the recovered retry credential -------------------------------
printf '%s\n' "$RECOVERED" > /app/recovered.txt

# --- 5. record the rewritten main history ------------------------------------
git -C /app/repo log --format='%H' --reverse main > /app/rebased_history

# --- 6. record the exact push + deploy-trigger command list ------------------
SHA=$(git -C /app/repo rev-parse --short=12 main)
cat > /app/push_commands.sh <<EOF
#!/bin/bash
# Deploy command list for the sanitized Paloma Studio tree at /app/repo.
set -e
REMOTE=gitdev@127.0.0.1:/srv/git/paloma.git
SHA=\$(git -C /app/repo rev-parse --short=12 main)
cat <<EOX
git push "\$REMOTE" main:main
curl -ksS -X POST "https://deploy.paloma.example/hook/\$SHA" -H "X-Deploy-Token: [REDACTED_API_KEY]"
EOX
EOF
chmod +x /app/push_commands.sh

echo "oracle complete: recovered=$RECOVERED head=$SHA"

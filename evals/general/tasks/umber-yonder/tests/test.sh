#!/bin/bash
# Verifier for "umber-yonder" (executes-deliverable).
# Checks every deliverable with literal /app paths, derives expectations
# independently from the PRISTINE remote (/srv/git/paloma.git), re-runs the
# reusable scrubber /app/repurge.py on fresh hidden incident repos, and also
# exercises a malformed (non-repository) input. Writes reward to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
git config --global --add safe.directory '*' 2>/dev/null || true

python3 - <<'PYEOF'
import json, os, re, subprocess, sys, tarfile

API_RE = re.compile(rb"\b[A-Z]{2,6}-[A-F0-9]{4}-[A-F0-9]{4}\b")
REC_RE = re.compile(rb"\b[A-Z]{2,5}:[0-9a-f]{8}\b")

failures = []

def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True)

def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True)

def all_objects(repo):
    out = subprocess.run(["git", "-C", repo, "cat-file", "--batch-all-objects",
                          "--batch"], capture_output=True).stdout
    res = []
    pos = 0; n = len(out)
    while pos < n:
        nl = out.find(b"\n", pos)
        if nl < 0: break
        hdr = out[pos:nl].split()
        if len(hdr) < 3: break
        typ = hdr[1]; size = int(hdr[2]); start = nl + 1
        if typ in (b"blob", b"commit"):
            res.append(out[start:start + size])
        pos = start + size
        if pos < n and out[pos:pos + 1] == b"\n": pos += 1
    return res

def worktree_data(repo):
    out = git(repo, "ls-files", "-z").stdout
    for p in out.split(b"\0"):
        if not p: continue
        fp = os.path.join(repo, os.fsdecode(p))
        try:
            with open(fp, "rb") as f: yield f.read()
        except OSError: continue

def vals_in(data):
    a = set(m.group(0) for m in API_RE.finditer(data))
    r = set(m.group(0) for m in REC_RE.finditer(data))
    return a, r

def secrets_of(repo):
    """Return (api_set, recovery_bytes_or_None) discovered from a repo."""
    api, rec = set(), set()
    for d in all_objects(repo):
        a, r = vals_in(d)
        api |= a; rec |= r
    wt_rec = set()
    for d in worktree_data(repo):
        _a, r = vals_in(d); wt_rec |= r
    rec -= wt_rec
    recovery = sorted(rec)[0] if rec else None
    return api, recovery

def object_clean(repo, needles):
    low = []
    for nd in needles: low.append(nd.lower())
    for d in all_objects(repo):
        l = d.lower()
        for nd in low:
            if nd in l: return False
    for d in worktree_data(repo):
        l = d.lower()
        for nd in low:
            if nd in l: return False
    return True

def content(repo, rev, path):
    r = git(repo, "show", "%s:%s" % (rev, path))
    return r.stdout if r.returncode == 0 else None

def tree_files(repo, rev="HEAD"):
    r = git(repo, "ls-tree", "-r", "--name-only", rev)
    return [p for p in r.stdout.decode().splitlines() if p]

PRIS = "/srv/git/paloma.git"
REPO = "/app/repo"

# =========================== MAIN scenario ==============================
if not os.path.isdir(os.path.join(REPO, ".git")):
    failures.append("deliverable /app/repo is not a git repository")
else:
    pris_api, pris_rec = secrets_of(PRIS)
    # expectations
    for delim, tag in [(PRIS, "pristine"), (REPO, "sanitized")]:
        pass
    # 1. expunged from every object + working tree
    needles = sorted(pris_api) + ([pris_rec] if pris_rec else [])
    if not object_clean(REPO, needles):
        failures.append("main: secret residue remains in /app/repo objects/worktree")
    # 2. byte-identical unrelated files
    for path in tree_files(PRIS):
        pb = content(PRIS, "HEAD", path)
        sb = content(REPO, "HEAD", path)
        if pb is None:
            continue
        if sb is None:
            failures.append("main: %s missing after work" % path); continue
        contains = any(v in pb or v.lower() in pb.lower() for v in needles)
        if contains:
            if any(v in sb or v.lower() in sb.lower() for v in needles):
                failures.append("main: secret still in file %s" % path)
            if b"[REDACTED_API_KEY]" not in sb and b"[REDACTED_CREDENTIAL]" not in sb:
                failures.append("main: %s lacks a placeholder" % path)
        else:
            if sb != pb:
                failures.append("main: unrelated file %s changed bytes" % path)
    # 3. commit messages clean
    for d in all_objects(REPO):
        pass
    # 4. history really rewritten
    h_pris = git(PRIS, "rev-parse", "HEAD").stdout.decode().strip()
    h_repo = git(REPO, "rev-parse", "HEAD").stdout.decode().strip()
    if h_repo == h_pris:
        failures.append("main: history was not rewritten (HEAD unchanged)")

    # 5. recovered.txt == recovery secret
    if pris_rec:
        if not os.path.exists("/app/recovered.txt"):
            failures.append("main: /app/recovered.txt missing")
        else:
            got = open("/app/recovered.txt").read().strip()
            if got != pris_rec.decode():
                failures.append("main: /app/recovered.txt != recovered secret (%r != %r)"
                                % (got, pris_rec.decode()))

    # 6. rebased_history == rewritten main history
    if os.path.exists("/app/rebased_history"):
        want = git(REPO, "log", "--format=%H", "--reverse", "main").stdout.decode().split()
        have = [ln for ln in open("/app/rebased_history").read().splitlines() if ln.strip()]
        if have != want:
            failures.append("main: rebased_history does not match rewritten main history")
    else:
        failures.append("main: /app/rebased_history missing")

    # 7. push_commands.sh: executable + prints the exact push/trigger list
    pc = "/app/push_commands.sh"
    if not os.path.exists(pc) or not os.access(pc, os.X_OK):
        failures.append("main: /app/push_commands.sh missing or not executable")
    else:
        short = git(REPO, "rev-parse", "--short=12", "main").stdout.decode().strip()
        r = run(["bash", pc])
        out = r.stdout.decode()
        if "gitdev@127.0.0.1:/srv/git/paloma.git" not in out:
            failures.append("main: push_commands output lacks the remote URL")
        if "git push" not in out:
            failures.append("main: push_commands output lacks a push command")
        if short not in out:
            failures.append("main: push_commands output lacks the current short sha")
        if "[REDACTED_API_KEY]" not in out:
            failures.append("main: push_commands output lacks the placeholder token")
        if any(v.decode().lower() in out.lower() for v in needles):
            failures.append("main: push_commands output leaks a secret")

    # 8. reusable scrubber deliverable present + executable
    if not os.path.exists("/app/repurge.py"):
        failures.append("main: /app/repurge.py (reusable scrubber) missing")
    elif not os.access("/app/repurge.py", os.X_OK):
        failures.append("main: /app/repurge.py not executable")

# =========================== HIDDEN scenarios ============================
hidden = sorted(x for x in os.listdir("/tests/hidden") if x.endswith(".tar.gz"))
if not hidden:
    failures.append("no hidden incident fixtures found")

work = "/tmp/hcw"
subprocess.run(["rm", "-rf", work]); os.makedirs(work)

for name in hidden:
    tag = name[:-7]
    src = os.path.join(work, tag + "_src")
    pris = os.path.join(work, tag + "_pristine")
    for d in (src, pris):
        os.makedirs(d)
        try:
            with tarfile.open(os.path.join("/tests/hidden", name)) as tf:
                tf.extractall(d)
        except Exception as exc:
            failures.append("%s: cannot extract: %r" % (tag, exc)); continue

    exp_api, exp_rec = secrets_of(pris)

    out = run(["python3", "/app/repurge.py", src, os.path.join(work, tag + ".json")])
    res = {}
    try:
        res = json.load(open(os.path.join(work, tag + ".json")))
    except Exception:
        failures.append("%s: repurge did not write a valid result json" % tag)

    if res.get("ok") is not True:
        failures.append("%s: repurge reported ok=%r" % (tag, res.get("ok")))
        continue

    got_rec = res.get("recovered")
    exp_rec_s = exp_rec.decode() if exp_rec else None
    if got_rec != exp_rec_s:
        failures.append("%s: recovered=%r expected=%r" % (tag, got_rec, exp_rec_s))

    needles = sorted(exp_api) + ([exp_rec] if exp_rec else [])
    if not object_clean(src, needles):
        failures.append("%s: secret residue remains after repurge" % tag)

    # byte-level checks against pristine
    for path in tree_files(pris):
        pb = content(pris, "HEAD", path)
        sb = content(src, "HEAD", path)
        if pb is None: continue
        if sb is None:
            failures.append("%s: %s disappeared" % (tag, path)); continue
        contains = any(v in pb or v.lower() in pb.lower() for v in needles)
        if contains:
            if any(v in sb or v.lower() in sb.lower() for v in needles):
                failures.append("%s: secret still in file %s" % (tag, path))
            if b"[REDACTED_API_KEY]" not in sb and b"[REDACTED_CREDENTIAL]" not in sb:
                failures.append("%s: %s lacks a placeholder" % (tag, path))
        else:
            if sb != pb:
                failures.append("%s: unrelated file %s changed bytes" % (tag, path))

# ======================= MALFORMED input ==================================
mdir = os.path.join(work, "not_a_repo")
os.makedirs(mdir)
open(os.path.join(mdir, "x"), "w").write("hi")
r = run(["python3", "/app/repurge.py", mdir, os.path.join(work, "mal.json")])
if r.returncode != 0:
    failures.append("malformed: repurge crashed (rc=%d) instead of exiting 0" % r.returncode)
else:
    try:
        mres = json.load(open(os.path.join(work, "mal.json")))
        if mres.get("ok") is not False:
            failures.append("malformed: expected ok=false for a non-repository input")
    except Exception:
        failures.append("malformed: no result json for non-repository input")

# ================================= result =================================
if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF

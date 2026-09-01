#!/bin/bash
# Oracle for zephyr-engine: performs the REAL recovery, scrubs the repo,
# patches the upload filter, and regenerates every deliverable. Never reads
# /tests and only uses literal /app paths.
set -eu

BEACON=17

# ---------------------------------------------------------------------------
# 1) Write the solver and run it. It does the enumeration, sha1 selection,
#    probe, extraction and answer.json generation.
# ---------------------------------------------------------------------------
cat > /app/solve.py <<'PY'
import json, hashlib, os, re, shutil, subprocess, sys
import zephyr_gen as z

BEACON = 17

def scan_candidates():
    cands = []
    for s in range(0, z.SEED_RANGE_HI):
        if not z.commissioned(s):
            continue
        tok = z.emit_flare(s)
        if z.is_well_formed(tok):
            cands.append((s, tok))
    cands.sort(key=lambda p: p[0])
    return cands

def af_count(token):
    d = hashlib.sha1(token.encode("utf-8")).hexdigest()
    return sum(1 for c in d if c in "abcdef")

cands = scan_candidates()
# Part 1: write every well-formed candidate, one per line, ascending seed.
with open("/app/candidates.txt", "w") as fh:
    for s, tok in cands:
        fh.write(tok + "\n")

# Part 2: select the active flare via the sha1 hex letter-count beacon (K=BEACON).
active = [(s, tok) for (s, tok) in cands if af_count(tok) == BEACON]
assert len(active) == 1, "active candidate must be unique"
aseed, password = active[0]

# Part 3: password-hash probe -> /app/vault.hash
probe = subprocess.run(["7z", "l", "-slt", "/app/vault.7z"],
                       capture_output=True, text=True).stdout
with open("/app/vault.hash", "w") as fh:
    fh.write(probe)
if "AES" not in probe:
    raise SystemExit("probe did not report AES encryption")

# Part 4: crack/extract the member with the recovered password.
out_dir = "/app/_recover"
if os.path.isdir(out_dir):
    shutil.rmtree(out_dir)
os.makedirs(out_dir)
r = subprocess.run(["7z", "x", "-y", "-p" + password, "-o" + out_dir, "/app/vault.7z"],
                   capture_output=True, text=True)
if r.returncode != 0:
    raise SystemExit("extraction failed with recovered password")
member = os.path.join(out_dir, "credentials", "creds.txt")
if not os.path.isfile(member):
    raise SystemExit("member credential file missing")
with open(member) as fh:
    creds = fh.read()
shutil.copyfile(member, "/app/creds.txt")

def extract(prefix):
    for line in creds.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    raise SystemExit("missing creds field " + prefix)

creds_user = extract("user=")
creds_secret = extract("secret=")
endpoint = extract("endpoint=")

# Part 5: recovered-credentials result.
answer = {
    "password": password,
    "active_seed": aseed,
    "candidate_count": len(cands),
    "beacon": BEACON,
    "probed": True,
    "member": "creds.txt",
    "creds_user": creds_user,
    "creds_secret": creds_secret,
    "endpoint": endpoint,
}
with open("/app/answer.json", "w") as fh:
    json.dump(answer, fh, indent=2)
    fh.write("\n")

print("recovered password=%s from seed=%d candidates=%d"
      % (password, aseed, len(cands)))
PY

python3 /app/solve.py

# ---------------------------------------------------------------------------
# 6) Reusable secret scrubber + scrub /app/team
# ---------------------------------------------------------------------------
cat > /app/scrub.py <<'PY'
#!/usr/bin/env python3
import json, os, re, sys

SECRET_RE = re.compile(r"[A-Z0-9]{3}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{2}")
DELETE_EXTS = {".bak", ".orig", ".tmp"}

def scrub(root):
    removed = 0
    deleted = []
    for dirpath, dirnames, filenames in os.walk(root):
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if os.path.splitext(fn)[1].lower() in DELETE_EXTS:
                os.remove(p)
                deleted.append(os.path.relpath(p, root))
                continue
            try:
                with open(p, "r", errors="ignore") as fh:
                    text = fh.read()
            except OSError:
                continue
            new, n = SECRET_RE.subn("[REDACTED]", text)
            if n:
                with open(p, "w") as fh:
                    fh.write(new)
                removed += n
    return {"removed": removed, "deleted": deleted}

if __name__ == "__main__":
    root = sys.argv[1]
    result = scrub(root)
    print(json.dumps(result))
PY
python3 /app/scrub.py /app/team > /dev/null

# ---------------------------------------------------------------------------
# 7) Harden the jar-upload filename filter.
# ---------------------------------------------------------------------------
cat > /app/upload/sanitizer.py <<'PY'
"""Upload filter for the Zephyr web console (hardened).

`sanitize_upload_filename` maps an incoming upload's raw filename to the safe
name to persist, or '' when the upload is unacceptable. Blocks path traversal
and dangerous-extension mask names.
"""

DANGEROUS_EXTS = {".jsp", ".war", ".js", ".jspx", ".sh", ".bat"}


def sanitize_upload_filename(raw):
    if raw is None:
        return ""
    name = raw.strip()
    if name == "":
        return ""
    # Traversal: '/', '\', or a '..' component.
    norm = name.replace("\\", "/")
    if "/" in norm or ".." in norm:
        return ""
    # Mask: final extension in the dangerous set.
    dot = name.rfind(".")
    if dot >= 0:
        if name[dot:].lower() in DANGEROUS_EXTS:
            return ""
    return name
PY

# Smoke checks on the hardened filter.
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location("san", "/app/upload/sanitizer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.sanitize_upload_filename("../etc/passwd") == ""
assert m.sanitize_upload_filename("weapon.jar.jsp") == ""
assert m.sanitize_upload_filename("x.jsp") == ""
assert m.sanitize_upload_filename("ok.jar") == "ok.jar"
print("sanitizer smoke ok")
PY

echo "zephyr-engine oracle finished"
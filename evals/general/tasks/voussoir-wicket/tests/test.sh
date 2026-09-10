#!/bin/bash
# Verifier for voussoir-wicket (executes-deliverable, system_administration).
#
# Asserts, on the agent's result /app/data and then on every hidden
# generalization tree:
#   1. size budget (policy.json budget_bytes) is met;
#   2. every file that was removed is junk per the tree's own policy --
#      deleting anything else (and in particular anything the retention
#      manifest lists) is a fail;
#   3. the retained areas are bit-identical: same path set, same content
#      (sha256), same mode, uid, gid and mtime_ns, for files and
#      directories alike -- so a naive `find -delete` / glob `rm -rf` or a
#      delete-and-recreate "restore" trick is caught;
#   4. nothing new appeared inside the tree.
#
# The visible case is checked against the generated pristine catalog
# (tests/golden_visible/expected.json -- content+stat recorded at build time
# by the same deterministic generator the image uses). Hidden cases are
# checked by re-running the deliverable /app/cleanup.py on a fresh copy of
# each hidden tree and comparing against the pristine copy, so the reference
# is derived, never hard-coded.
#
# Writes /logs/verifier/reward.txt: exactly 1 or 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if [ ! -f /app/cleanup.py ]; then
  echo "missing deliverable /app/cleanup.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import ast
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = "/app/data"
TOOL = "/app/cleanup.py"
CATALOG = "/tests/golden_visible/expected.json"
BLOCK = 1 << 16

failures = []


def fail(msg):
    failures.append(msg)


def ok(cond, msg):
    if not cond:
        fail(msg)


# ---------------------------------------------------------------- 0) source sanity
sz = len(gzip.compress(open(TOOL, "rb").read()))
ok(sz <= 20000, "cleanup.py gzip=%d exceeds ceil 20000" % sz)

imports = set()
for node in ast.walk(ast.parse(open(TOOL).read())):
    if isinstance(node, ast.Import):
        for a in node.names:
            imports.add(a.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom) and node.module:
        imports.add(node.module.split(".")[0])
bad = sorted(i for i in imports if i not in sys.stdlib_module_names)
ok(not bad, "cleanup.py imports non-stdlib modules: %s" % bad)


# ---------------------------------------------------------------- policy semantics
def load_json(path):
    with open(path, "r") as fh:
        return json.load(fh)


def manifest_roots(root, name):
    p = os.path.join(root, name)
    if not os.path.isfile(p):
        return None
    out = []
    with open(p, "r") as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            out.append(ln.rstrip("/"))
    return out


def under(rel, roots):
    for r in roots:
        if rel == r or rel.startswith(r + "/"):
            return True
    return False


def junk_match(rel, size, pol):
    j = pol.get("junk", {})
    suffixes = j.get("suffixes", [])
    prefixes = j.get("prefixes", [])
    dir_names = j.get("dir_names", [])
    min_size = j.get("min_size_bytes", 0)
    if size < min_size:
        return False
    base = rel.rsplit("/", 1)[-1]
    if any(base.endswith(s) for s in suffixes):
        return True
    if any(base.startswith(p) for p in prefixes):
        return True
    parts = rel.split("/")
    if len(parts) > 1 and any(dn in parts[:-1] for dn in dir_names):
        return True
    return False


def snapshot(root, hash_under=None):
    """rel -> stat dict for every regular file (dirs into second dict)."""
    files, dirs = {}, {}
    base = os.path.abspath(root)
    if not os.path.isdir(base):
        return files, dirs
    for dp, dns, fns in os.walk(base):
        rdir = os.path.relpath(dp, base)
        if rdir == ".":
            rdir = ""
        if rdir:
            st = os.stat(dp)
            dirs[rdir] = {"mode": st.st_mode, "uid": st.st_uid,
                          "gid": st.st_gid, "mtime_ns": st.st_mtime_ns}
        for fn in fns:
            fp = os.path.join(dp, fn)
            rel = fn if not rdir else rdir + "/" + fn
            st = os.stat(fp)
            ent = {"size": st.st_size, "mode": st.st_mode,
                   "uid": st.st_uid, "gid": st.st_gid,
                   "mtime_ns": st.st_mtime_ns}
            if hash_under is not None and under(rel, hash_under):
                h = hashlib.sha256()
                with open(fp, "rb") as fh:
                    for chunk in iter(lambda: fh.read(BLOCK), b""):
                        h.update(chunk)
                ent["sha256"] = h.hexdigest()
            files[rel] = ent
    return files, dirs


def retained_ok(new_files, new_dirs, old_files, old_dirs, roots, label):
    """Retained areas in `old` must exist in `new` bit-identically."""
    for rel, ent in old_files.items():
        if not under(rel, roots):
            continue
        ne = new_files.get(rel)
        if ne is None:
            fail("%s: retained file removed: %s" % (label, rel))
            continue
        ok(ne["size"] == ent["size"],
           "%s: retained file size changed: %s" % (label, rel))
        ok(ne["mode"] == ent["mode"],
           "%s: retained file mode changed: %s" % (label, rel))
        ok(ne["uid"] == ent["uid"],
           "%s: retained file owner changed: %s" % (label, rel))
        ok(ne["gid"] == ent["gid"],
           "%s: retained file group changed: %s" % (label, rel))
        ok(ne["mtime_ns"] == ent["mtime_ns"],
           "%s: retained file mtime changed: %s" % (label, rel))
        ok(ne.get("sha256") == ent.get("sha256") and ent.get("sha256"),
           "%s: retained file content changed: %s" % (label, rel))
    for rel, ent in old_dirs.items():
        if not under(rel, roots):
            continue
        nd = new_dirs.get(rel)
        if nd is None:
            fail("%s: retained directory removed: %s" % (label, rel))
            continue
        ok(nd["mode"] == ent["mode"],
           "%s: retained dir mode changed: %s" % (label, rel))
        ok(nd["uid"] == ent["uid"],
           "%s: retained dir owner changed: %s" % (label, rel))
        ok(nd["gid"] == ent["gid"],
           "%s: retained dir group changed: %s" % (label, rel))
        ok(nd["mtime_ns"] == ent["mtime_ns"],
           "%s: retained dir mtime changed: %s" % (label, rel))


def outcome_checks(new_files, old_files, old_dirs, roots, pol, label):
    """Budget met, nothing new, only junk removed."""
    total = sum(e["size"] for e in new_files.values())
    budget = pol["budget_bytes"]
    ok(total <= budget,
       "%s: tree size %d exceeds budget %d" % (label, total, budget))

    for rel in new_files:
        ok(rel in old_files,
           "%s: new file appeared that was not in the original tree: %s"
           % (label, rel))

    for rel, ent in old_files.items():
        if rel in new_files:
            continue
        if under(rel, roots):
            fail("%s: retained file deleted: %s" % (label, rel))
        elif not junk_match(rel, ent["size"], pol):
            fail("%s: non-junk file deleted: %s (size %d)"
                 % (label, rel, ent["size"]))


def run_hidden_case(case_path, label):
    tree = os.path.join(case_path, "tree")
    if not os.path.isdir(tree):
        fail("%s: hidden case has no tree/ dir" % label)
        return
    work = "/tmp/vw-verify/%s" % label
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    r = subprocess.run(["cp", "-a", tree + "/.", work + "/"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("%s: cannot stage tree copy: %s" % (label, r.stderr.strip()))
        return

    rr = subprocess.run([sys.executable, TOOL, work],
                        capture_output=True, text=True)
    ok(rr.returncode == 0,
       "%s: cleanup.py exited %d: %s" % (label, rr.returncode,
                                         rr.stderr.strip()[:400]))

    pol_path = os.path.join(work, "policy.json")
    if not os.path.isfile(pol_path):
        fail("%s: policy.json missing after cleanup run" % label)
        return
    try:
        pol = load_json(pol_path)
    except Exception as exc:
        fail("%s: policy unreadable: %s" % (label, exc))
        return
    roots = manifest_roots(work, pol.get("retention_manifest", ""))
    if roots is None:
        fail("%s: retention manifest missing after cleanup run" % label)
        return

    before, before_dirs = snapshot(tree, hash_under=roots)
    after, after_dirs = snapshot(work, hash_under=roots)
    outcome_checks(after, before, before_dirs, roots, pol, label)
    retained_ok(after, after_dirs, before, before_dirs, roots, label)


# ---------------------------------------------------------------- visible case
ok(os.path.isdir(ROOT), "/app/data missing")
ok(os.path.isfile(CATALOG), "verifier-internal catalog missing")
if os.path.isdir(ROOT) and os.path.isfile(CATALOG):
    catalog = load_json(CATALOG)
    pol_path = os.path.join(ROOT, "policy.json")
    if not os.path.isfile(pol_path):
        fail("visible: policy.json missing")
    else:
        pol = load_json(pol_path)
        if pol.get("budget_bytes") != catalog["budget_bytes"]:
            fail("visible: policy budget does not match the build catalog")
        manifest_name = pol.get("retention_manifest", "")
        live_roots = manifest_roots(ROOT, manifest_name)
        if live_roots is None:
            fail("visible: retention manifest missing")
        elif live_roots != catalog["protected_roots"]:
            fail("visible: retention manifest roots changed")
        else:
            live, live_dirs = snapshot(ROOT, hash_under=live_roots)
            outcome_checks(live, catalog["files"], catalog["protected_dirs"],
                           live_roots, pol, "visible")
            retained_ok(live, live_dirs, catalog["files"],
                        catalog["protected_dirs"], live_roots, "visible")

# ---------------------------------------------------------------- hidden cases
hidden = "/tests/hidden"
n_hidden = 0
if os.path.isdir(hidden):
    for name in sorted(os.listdir(hidden)):
        case_path = os.path.join(hidden, name)
        if not os.path.isdir(case_path):
            continue
        n_hidden += 1
        run_hidden_case(case_path, name)
ok(n_hidden >= 2, "expected at least 2 hidden cases (found %d)" % n_hidden)

# ---------------------------------------------------------------- verdict
if failures:
    print("FAILURES (%d):" % len(failures))
    for m in failures:
        print("  - " + m)
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

print("ALL PASS: visible + %d hidden case(s); cleanup.py gzip=%d"
      % (n_hidden, sz))
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1")
sys.exit(0)
PY
#!/bin/bash
# Verifier for poppy-kiln: EXECUTES the deliverable /app/skeleton.py on the
# visible catalog and on every hidden case under /tests/hidden, enforcing the
# no-modify rule on /app/catalog.txt. Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_CATALOG_SHA="faa0d52b350fceb7ceea6ae05982e16d03ac72c80a7e3d5733b87b9b44fe94a8"

no_modify_broken=0
if [ ! -f /app/catalog.txt ]; then
    echo "no-modify: /app/catalog.txt missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/catalog.txt | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CATALOG_SHA" ]; then
        echo "no-modify: /app/catalog.txt was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import os, re, shutil, subprocess, sys

SOLVE = "/app/skeleton.py"
no_modify_broken = int(sys.argv[1])
failures = []

ENTRY_RE = re.compile(r"^([0-9a-f]{64})  (.+)$")


def reference_parse(path):
    """Independent parse of a catalog into its expected set of file paths.
    Returns (files, fatal) where fatal is None or an error string."""
    files = []
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            if line.lstrip().startswith("#"):
                continue
            m = ENTRY_RE.match(line)
            if not m:
                return files, "malformed"
            rel = m.group(2)
            if rel.startswith("/"):
                return files, "absolute"
            if any(p == ".." for p in rel.split("/")):
                return files, "dotdot"
            if rel not in files:
                files.append(rel)
    for a in files:
        for b in files:
            if a != b and b.startswith(a + "/"):
                return files, "conflict"
    return files, None


def tree_files(root):
    """All regular files under root, relative, plus a flag if root exists."""
    if not os.path.isdir(root):
        return None
    found = set()
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            full = os.path.join(dirpath, name)
            if not os.path.isfile(full) or os.path.islink(full):
                return None
            found.add(os.path.relpath(full, root))
    return found


def run_ok_case(catalog, outdir, pre_populate=None):
    """Run skeleton.py expecting success; verify the exact zero-byte leaf set."""
    if os.path.exists(outdir):
        shutil.rmtree(outdir)
    os.makedirs(outdir)
    if pre_populate:
        for rel, content in pre_populate.items():
            dest = os.path.join(outdir, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as fh:
                fh.write(content)
    r = subprocess.run([sys.executable, SOLVE, catalog, outdir],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return "exit %d" % r.returncode
    files, fatal = reference_parse(catalog)
    if fatal:
        return "ok-case catalog unexpectedly fatal: %s" % fatal
    got = tree_files(outdir)
    if got is None:
        return "outdir missing or contains a non-regular entry"
    want = set(files)
    if got != want:
        return "leaf set mismatch: missing=%s extra=%s" % (
            sorted(want - got)[:5], sorted(got - want)[:5])
    for rel in want:
        if os.path.getsize(os.path.join(outdir, rel)) != 0:
            return "leaf %r is not zero bytes" % rel
    return None


def run_fatal_case(catalog, outdir):
    """Run skeleton.py expecting refusal: non-zero exit, no leaf files written."""
    if os.path.exists(outdir):
        shutil.rmtree(outdir)
    r = subprocess.run([sys.executable, SOLVE, catalog, outdir],
                       capture_output=True, text=True, timeout=120)
    if r.returncode == 0:
        return "expected non-zero exit"
    got = tree_files(outdir)
    if got:
        return "leaf files were written despite fatal catalog: %s" % sorted(got)[:5]
    return None


if no_modify_broken:
    failures.append("visible catalog modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/skeleton.py")
else:
    # ---- visible case: re-run on the live catalog and on /app/skeleton ----
    err = run_ok_case("/app/catalog.txt", "/tmp/pk_vis_out")
    if err:
        failures.append("visible re-run failed: %s" % err)
    if not os.path.isdir("/app/skeleton"):
        failures.append("missing /app/skeleton (visible deliverable)")
    else:
        files, fatal = reference_parse("/app/catalog.txt")
        got = tree_files("/app/skeleton")
        if fatal or got is None or got != set(files):
            failures.append("/app/skeleton does not match the catalog")
        else:
            for rel in files:
                if os.path.getsize(os.path.join("/app/skeleton", rel)) != 0:
                    failures.append("/app/skeleton leaf %r not zero bytes" % rel)
                    break

    # ---- hidden cases ----
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden) or not os.listdir(hidden):
        failures.append("no hidden cases present")
    for case in sorted(os.listdir(hidden)):
        base = os.path.join(hidden, case)
        catalog = os.path.join(base, "catalog.txt")
        if not os.path.isfile(catalog):
            failures.append("hidden '%s' malformed" % case)
            continue
        outdir = "/tmp/pk_hidden_" + case
        _files, fatal = reference_parse(catalog)
        if fatal:
            err = run_fatal_case(catalog, outdir)
        elif case == "ok_truncate":
            err = run_ok_case(
                catalog, outdir,
                pre_populate={"a/b/keep.bin": b"stale payload bytes" * 10})
        else:
            err = run_ok_case(catalog, outdir)
        if err:
            failures.append("hidden case '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

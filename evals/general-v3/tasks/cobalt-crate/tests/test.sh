#!/bin/bash
# Verifier for cobalt-crate. Checks the deliverable /app/unpack.py exists,
# re-executes it on the visible store and on every hidden store under
# /tests/hidden, and asserts the reconstructed trees match the reference
# (exact name set, sizes, SHA-256 digests); corrupt/unsafe stores must fail
# with a non-zero exit and produce no output files. Also checks the visible
# /app/unpacked deliverable and the no-modify rule on /app/store. Writes
# REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

PRISTINE_MANIFEST_SHA="5fd0016a64f013a6610761bd742b2c4d47b6b1b3ec98e64eacd1078017be9931"

export PRISTINE_MANIFEST_SHA
python3 - <<'PY'
import hashlib, json, os, shutil, subprocess, sys, tempfile

TOOL = "/app/unpack.py"
failures = []

# no-modify guard on the supplied store
sha = ""
try:
    with open("/app/store/manifest.json", "rb") as fh:
        sha = hashlib.sha256(fh.read()).hexdigest()
except OSError:
    pass
if sha != os.environ["PRISTINE_MANIFEST_SHA"]:
    failures.append("/app/store was modified or manifest missing")

if not os.path.isfile(TOOL):
    failures.append("missing /app/unpack.py")


def tree_files(root):
    """Map relpath -> (size, sha256) for every regular file under root."""
    out = {}
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "rb") as fh:
                data = fh.read()
            out[rel] = (len(data), hashlib.sha256(data).hexdigest())
    return out


def _norm_file(v):
    """Accept either {'size':..,'sha256':..} or a (size, sha) pair."""
    if isinstance(v, dict):
        return (int(v["size"]), str(v["sha256"]))
    return (int(v[0]), str(v[1]))


def check_success(store, truth, label):
    """Run the tool and require an exact tree match against truth."""
    outdir = tempfile.mkdtemp(prefix="cratechk-")
    try:
        dest = os.path.join(outdir, "out")
        r = subprocess.run([sys.executable, TOOL, "--store", store,
                            "--out", dest], capture_output=True, timeout=120)
        if r.returncode != 0:
            return "%s: unpack exited %d: %s" % (
                label, r.returncode, r.stderr.decode()[-150:])
        got = tree_files(dest)
        want = {p: _norm_file(v) for p, v in truth.items()}
        if got != want:
            missing = sorted(set(want) - set(got))
            extra = sorted(set(got) - set(want))
            diff = sorted(p for p in set(got) & set(want)
                          if got[p] != want[p])
            return ("%s: tree mismatch (missing=%s extra=%s differ=%s)"
                    % (label, missing[:5], extra[:5], diff[:5]))
        return None
    except subprocess.TimeoutExpired:
        return "%s: unpack timed out" % label
    except Exception as exc:  # guard all parses
        return "%s: checker error: %r" % (label, exc)
    finally:
        shutil.rmtree(outdir, ignore_errors=True)


def check_failure(store, label):
    """Corrupt/unsafe store: non-zero exit and no output files at all."""
    outdir = tempfile.mkdtemp(prefix="cratechk-")
    try:
        dest = os.path.join(outdir, "out")
        r = subprocess.run([sys.executable, TOOL, "--store", store,
                            "--out", dest], capture_output=True, timeout=120)
        if r.returncode == 0:
            return "%s: corrupt store accepted (exit 0)" % label
        produced = tree_files(dest) if os.path.isdir(dest) else {}
        if produced:
            return "%s: wrote files despite failing: %s" % (
                label, sorted(produced)[:5])
        return None
    except Exception as exc:  # guard all parses
        return "%s: checker error: %r" % (label, exc)
    finally:
        shutil.rmtree(outdir, ignore_errors=True)


if os.path.isfile(TOOL) and not failures:
    # visible deliverable: /app/unpacked must match the store manifest
    try:
        with open("/app/store/manifest.json", encoding="utf-8") as fh:
            man = json.load(fh)
        want = {f["path"]: (f["size"], f["sha256"]) for f in man["files"]}
        if not os.path.isdir("/app/unpacked"):
            failures.append("missing /app/unpacked")
        else:
            got = tree_files("/app/unpacked")
            if got != want:
                failures.append("/app/unpacked does not match /app/store")
            # the deliverable must also re-run cleanly on the visible store
            err = check_success("/app/store", want, "visible rerun")
            if err:
                failures.append(err)
    except Exception as exc:  # guard all parses
        failures.append("visible check error: %r" % exc)

    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            store = os.path.join(base, "store")
            cj = os.path.join(base, "case.json")
            try:
                with open(cj, encoding="utf-8") as fh:
                    meta = json.load(fh)
            except Exception as exc:  # guard all parses
                failures.append("hidden '%s': unreadable case.json (%r)"
                                % (c, exc))
                continue
            if not os.path.isdir(store):
                failures.append("hidden '%s': missing store" % c)
                continue
            if meta.get("expect_success"):
                err = check_success(store, meta.get("files", {}),
                                    "hidden '%s'" % c)
                if err:
                    failures.append(err)
            else:
                err = check_failure(store, "hidden '%s'" % c)
                if err:
                    failures.append(err)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

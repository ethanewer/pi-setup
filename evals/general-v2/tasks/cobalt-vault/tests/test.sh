#!/bin/bash
# Verifier for cobalt-vault (executes-deliverable). Imports /app/attack.py,
# calls recover_seed() on the visible and every hidden pairs file (including a
# synthetic malformed one), executes the CLI on visible + hidden scenarios, and
# byte-checks /app/seed.txt and /app/message.txt. Writes reward (1/0) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import importlib.util, json, os, subprocess, sys, tempfile

TOOL = "/app/attack.py"
VAULT = "/app/vault"
failures = []

def fail(m):
    failures.append(m)
    print("FAIL:", m)

mod = None
if not os.path.isfile(TOOL):
    fail("missing deliverable %s" % TOOL)
else:
    try:
        spec = importlib.util.spec_from_file_location("attack_mod", TOOL)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception as e:
        fail("cannot import %s: %r" % (TOOL, e))

if mod is not None and not callable(getattr(mod, "recover_seed", None)):
    fail("missing exported function recover_seed")
    mod = None

def run_cli(pairs, target, label):
    """Returns (seed_int, plain_hex) or (None, None) after recording failures."""
    r = subprocess.run(["python3", TOOL, pairs, target],
                       capture_output=True, text=True, timeout=180)
    if r.returncode != 0:
        fail("%s: CLI exited %d (stderr: %s)" % (label, r.returncode, (r.stderr or "")[:200]))
        return None, None
    seed = plain = None
    for ln in r.stdout.splitlines():
        if ln.startswith("seed="):
            try:
                seed = int(ln.split("=", 1)[1].strip())
            except Exception:
                pass
        elif ln.startswith("plain="):
            plain = ln.split("=", 1)[1].strip().lower()
    if seed is None or plain is None:
        fail("%s: CLI output missing seed=/plain= lines" % label)
    return seed, plain

def check_scenario(pairs, target, exp, label):
    if mod is not None:
        try:
            ks = mod.recover_seed(pairs)
        except Exception as e:
            fail("%s: recover_seed raised %r" % (label, e)); return
        if not isinstance(ks, int) or ks != exp["seed"]:
            fail("%s: recover_seed returned %r, want %d" % (label, ks, exp["seed"]))
            return
    seed, plain = run_cli(pairs, target, label)
    if seed is None:
        return
    if seed != exp["seed"]:
        fail("%s: seed %d != expected %d" % (label, seed, exp["seed"]))
    if (plain or "").lower() != exp["plain_hex"].lower():
        fail("%s: plain %r != expected %r" % (label, plain, exp["plain_hex"]))

if mod is not None:
    # malformed-pairs robustness: recover_seed must return -1, never raise
    bad = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
    bad.write("zzzz nothex\n12\nzz 1111\n")
    bad.close()
    try:
        v = mod.recover_seed(bad.name)
        if v != -1:
            fail("recover_seed(malformed) = %r, want -1" % v)
    except Exception as e:
        fail("recover_seed(malformed) raised %r" % e)
    v2 = None
    try:
        v2 = mod.recover_seed("/nonexistent/pairs.txt")
        if v2 != -1:
            fail("recover_seed(missing) = %r, want -1" % v2)
    except Exception as e:
        fail("recover_seed(missing) raised %r" % e)
    try:
        os.unlink(bad.name)
    except OSError:
        pass

    # ---- visible artifacts + deliverables ----
    vexp = None
    try:
        vexp = json.load(open("/tests/expected.json"))
    except Exception as e:
        fail("visible expected.json unreadable: %r" % e)
    if vexp is not None:
        if not (os.path.isfile(os.path.join(VAULT, "pairs.txt"))
                and os.path.isfile(os.path.join(VAULT, "target.hex"))):
            fail("visible artifacts missing")
        else:
            check_scenario(os.path.join(VAULT, "pairs.txt"),
                           os.path.join(VAULT, "target.hex"), vexp, "visible")
        if not os.path.isfile("/app/seed.txt"):
            fail("missing deliverable /app/seed.txt")
        else:
            try:
                got = None
                for ln in open("/app/seed.txt"):
                    ln = ln.strip()
                    if ln.startswith("seed="):
                        got = int(ln.split("=", 1)[1].strip())
                if got != vexp["seed"]:
                    fail("/app/seed.txt = %r, want seed=%d" % (got, vexp["seed"]))
            except Exception as e:
                fail("/app/seed.txt unreadable: %r" % e)
        if not os.path.isfile("/app/message.txt"):
            fail("missing deliverable /app/message.txt")
        else:
            try:
                msg = open("/app/message.txt").read().strip()
                if msg != vexp["message"]:
                    fail("/app/message.txt = %r, want %r" % (msg, vexp["message"]))
            except Exception as e:
                fail("/app/message.txt unreadable: %r" % e)

    # ---- hidden scenarios ----
    hroot = "/tests/hidden"
    cases = sorted(d for d in os.listdir(hroot)
                   if os.path.isdir(os.path.join(hroot, d))) if os.path.isdir(hroot) else []
    if len(cases) < 2:
        fail("expected >= 2 hidden scenarios, found %d" % len(cases))
    for name in cases:
        d = os.path.join(hroot, name)
        ep = os.path.join(d, "expected.json")
        if not (os.path.isfile(os.path.join(d, "pairs.txt"))
                and os.path.isfile(os.path.join(d, "target.hex"))
                and os.path.isfile(ep)):
            fail("hidden '%s' incomplete" % name)
            continue
        try:
            exp = json.load(open(ep))
        except Exception as e:
            fail("hidden '%s' expected.json unreadable: %r" % (name, e))
            continue
        check_scenario(os.path.join(d, "pairs.txt"), os.path.join(d, "target.hex"),
                       exp, "hidden:" + name)

print("failures:", len(failures))
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not failures else "0")
sys.exit(0)
PY
exit 0

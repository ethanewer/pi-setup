#!/bin/bash
# Verifier for quartz-hollow: guards the shipped inputs, EXECUTES the
# deliverable decoder (/app/derive.py) on the visible store and on every
# hidden store, and cross-checks the side-effect deliverable
# (/app/releases/commit.token) against a fresh run of the target application.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

failures=""

# Pristine digests of the shipped inputs (the instruction forbids modifying
# /app/signer.py and /app/store).
PIN_SIGNER="e7d141a56c633ca9745da0d712e42689ba83f6ae059769c856ea58bca89d9dbd"
PIN_TAPE="634af9623e242607b28f8c9c7788db30a6664c0a2fe7cafc434c612a4d0b347c"
PIN_UNPACK="91f1baa3f2cf376a241802731ded1809ebab72d5299acbb54a3df8d7d37c175c"
PIN_SPEC="2653a1a16f7f1f11598847530e851a7b5c746ab49c118f416b0f9c113eb0de2c"

for pair in "/app/signer.py $PIN_SIGNER" "/app/store/tape.bin $PIN_TAPE" \
            "/app/store/legacy_unpack.py $PIN_UNPACK" "/app/store/TAPE-FORMAT.txt $PIN_SPEC"; do
    set -- $pair
    if [ ! -f "$1" ]; then
        failures="$failures shipped input missing: $1;"
    elif [ "$(sha256sum "$1" | cut -d' ' -f1)" != "$2" ]; then
        failures="$failures shipped input modified: $1;"
    fi
done

# Visible pinned facts (known only to the verifier).
VIS_CRED_SHA="9c20200b003d08fd42a8658944e26d6d8aeb28925138219e75fa5ae85e2ee692"
SALT="cinder-tide-9"

python3 - "$VIS_CRED_SHA" "$SALT" <<'PY'
import hashlib, json, os, subprocess, sys, tempfile

vis_cred_sha = sys.argv[1]
salt = sys.argv[2]
failures = []


def body_digest(cred: str) -> str:
    return hashlib.sha256((salt + cred).encode("utf-8")).hexdigest()


def expected_token(cred: str) -> str:
    return "COMMITTED:%s:%s:%s\n" % (cred, hashlib.sha256(cred.encode("utf-8")).hexdigest(), body_digest(cred))


def run_derive(store_dir: str):
    r = subprocess.run([sys.executable, "/app/derive.py", store_dir],
                       capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        return None, "derive.py exited %d: %s" % (r.returncode, r.stderr.strip()[:200])
    out = r.stdout
    if not out.endswith("\n") or len(out.splitlines()) != 1:
        return None, "derive.py stdout must be exactly one line"
    return out.strip(), None


def run_signer(signer_path: str, cred: str, out_dir: str):
    env = dict(os.environ)
    env["RELEASE_DIR"] = out_dir
    r = subprocess.run([sys.executable, signer_path, cred],
                       capture_output=True, text=True, timeout=120, env=env)
    token = os.path.join(out_dir, "commit.token")
    if r.returncode != 0:
        return None, "signer exited %d: %s" % (r.returncode, r.stderr.strip()[:200])
    if not os.path.isfile(token):
        return None, "signer did not write commit.token (credential refused?)"
    with open(token) as fh:
        return fh.read(), None


# ------------------------------------------------------------- deliverables
if not os.path.isfile("/app/derive.py"):
    failures.append("missing /app/derive.py")

cred = None
if not failures:
    cred, err = run_derive("/app/store")
    if err:
        failures.append("visible derive failed: " + err)
    elif hashlib.sha256(cred.encode("utf-8")).hexdigest() != vis_cred_sha:
        failures.append("visible credential digest mismatch (wrong derivation)")

token_path = "/app/releases/commit.token"
if not os.path.isfile(token_path):
    failures.append("missing /app/releases/commit.token (app was not run)")
elif cred is not None:
    try:
        with open(token_path) as fh:
            got = fh.read()
        if got != expected_token(cred):
            failures.append("commit.token does not match a real signer run")
    except Exception as exc:
        failures.append("commit.token unreadable: %r" % (exc,))

# ------------------------------------------------------------- hidden cases
hidden_dir = "/tests/hidden"
n = 0
if os.path.isdir(hidden_dir):
    for name in sorted(os.listdir(hidden_dir)):
        base = os.path.join(hidden_dir, name)
        exp_path = os.path.join(base, "expected.json")
        tape_path = os.path.join(base, "store", "tape.bin")
        signer_path = os.path.join(base, "signer.py")
        if not all(os.path.isfile(p) for p in (exp_path, tape_path, signer_path)):
            failures.append("hidden case '%s' malformed" % name)
            continue
        try:
            with open(exp_path) as fh:
                exp = json.load(fh)
            want_cred = str(exp["credential"])
            want_sha = str(exp["sha256"])
            assert set(exp) == {"credential", "sha256"}
        except Exception as exc:
            failures.append("hidden case '%s' expected.json unreadable: %r" % (name, exc))
            continue
        n += 1
        with tempfile.TemporaryDirectory(prefix="quartz_h_") as tmp:
            # run the deliverable on the hidden store
            hcred, err = run_derive(os.path.join(base, "store"))
            if err:
                failures.append("hidden '%s': %s" % (name, err))
                continue
            if hcred != want_cred:
                failures.append("hidden '%s': credential mismatch" % name)
                continue
            if hashlib.sha256(hcred.encode("utf-8")).hexdigest() != want_sha:
                failures.append("hidden '%s': credential digest mismatch" % name)
                continue
            # run the (case-pinned) target app with the derived secret
            out_dir = os.path.join(tmp, "releases")
            got, err = run_signer(signer_path, hcred, out_dir)
            if err:
                failures.append("hidden '%s': %s" % (name, err))
                continue
            if got != expected_token(hcred):
                failures.append("hidden '%s': signer token mismatch" % name)
    if n < 2:
        failures.append("expected >=2 hidden cases, saw %d" % n)
else:
    failures.append("no hidden cases present")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

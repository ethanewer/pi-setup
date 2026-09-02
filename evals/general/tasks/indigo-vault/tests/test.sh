#!/bin/bash
# Verifier for indigo-vault: checks the visible-case deliverables, enforces
# the no-modify rule on the supplied /app fixtures, and EXECUTES the
# deliverable (/app/crack.sh) on the visible case and on every hidden
# hash/wordlist/archive fixture in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (agent must not modify them).
PRISTINE_ZIP_SHA="cfbc3e656439655edb382ed570cc16de0cb5dacf1f5878d4b14898b77379a329"
PRISTINE_HASH_SHA="8951c24d14d0527c3b570e962d23bc04acc66cb652e82998b07e203c6bd1d050"
PRISTINE_WORDLIST_SHA="4a6ad60f158c908aada58f83108d309a52d414473a036c16e8e80d511e365aa1"

no_modify_broken=0
for pair in \
    "/app/locker.zip:$PRISTINE_ZIP_SHA" \
    "/app/passwd.hash:$PRISTINE_HASH_SHA" \
    "/app/wordlist.txt:$PRISTINE_WORDLIST_SHA"; do
    path="${pair%%:*}"; want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

export NO_MODIFY_BROKEN="$no_modify_broken"
python3 - <<'PY'
import json, os, shutil, subprocess, sys, tempfile

CRACK = "/app/crack.sh"
failures = []

if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("visible inputs modified or missing (no-modify rule)")


def norm(obj):
    try:
        assert isinstance(obj, dict), obj
        assert set(obj.keys()) == {"password", "hash", "member", "code"}, sorted(obj.keys())
        return (str(obj["password"]), str(obj["hash"]).lower(),
                str(obj["member"]), str(obj["code"]))
    except Exception as exc:
        raise AssertionError("bad answer object: %r" % (exc,))


def run_crack(hash_file, wordlist, zip_path, out_dir, expected_path):
    try:
        r = subprocess.run(
            ["bash", CRACK, hash_file, wordlist, zip_path, out_dir],
            capture_output=True, text=True, timeout=180,
        )
        if r.returncode != 0:
            return False
        ans = os.path.join(out_dir, "answer.json")
        if not os.path.isfile(ans):
            return False
        with open(ans) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        if norm(got) != norm(want):
            return False
        member = os.path.join(out_dir, str(want["member"]))
        if not os.path.isfile(member):
            return False
        with open(member, "rb") as fh:
            return ("code=%s" % want["code"]).encode() in fh.read()
    except Exception:
        return False


if not os.path.isfile(CRACK):
    failures.append("missing /app/crack.sh")
else:
    # --- visible case: EXECUTE crack.sh on the live supplied fixtures ---
    vis_out = tempfile.mkdtemp(prefix="indigo_vis_")
    if not run_crack("/app/passwd.hash", "/app/wordlist.txt", "/app/locker.zip",
                     vis_out, "/tests/expected.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/answer.json must match too ---
    try:
        with open("/app/answer.json") as f:
            got = json.load(f)
        with open("/tests/expected.json") as f:
            want = json.load(f)
        if norm(got) != norm(want):
            failures.append("answer.json does not match visible expected")
    except Exception:
        failures.append("answer.json missing or unreadable")

    # --- hidden cases: fresh hash/wordlist/archive, run unchanged ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            if not all(os.path.isfile(os.path.join(base, n))
                       for n in ("passwd.hash", "wordlist.txt", "locker.zip",
                                 "expected.json")):
                failures.append("hidden '%s' malformed" % c)
                continue
            work = tempfile.mkdtemp(prefix="indigo_hc_")
            try:
                if not run_crack(os.path.join(base, "passwd.hash"),
                                 os.path.join(base, "wordlist.txt"),
                                 os.path.join(base, "locker.zip"),
                                 os.path.join(work, "out"),
                                 os.path.join(base, "expected.json")):
                    failures.append("hidden case '%s' failed" % c)
            finally:
                shutil.rmtree(work, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

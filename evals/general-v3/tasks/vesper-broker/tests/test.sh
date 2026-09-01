#!/bin/bash
# Verifier for vesper-broker: enforces the no-modify rule on the stock
# consumer, re-runs the deliverables (/app/gadget.py crafting /app/dispatch.msg
# and /app/dispatch.py consuming it) on the visible mission and on hidden
# missions in /tests/hidden, and requires the deserialization side effect to
# reappear. Writes REWARD (0/1) to /logs/verifier/reward.txt. Never crashes on
# malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_DISPATCH_SHA="29fc874f6bec1a72f911b25bbb7c94a77f4fbefd4b5ce0d7c4f3c7b7b6d73336"

no_modify_broken=0
if [ ! -f /app/dispatch.py ]; then
    echo "no-modify: /app/dispatch.py missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/dispatch.py | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_DISPATCH_SHA" ]; then
        echo "no-modify: /app/dispatch.py was modified" >&2
        no_modify_broken=1
    fi
fi

export NO_MODIFY_BROKEN="$no_modify_broken"
python3 - <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile

GADGET = "/app/gadget.py"
CONSUMER = "/app/dispatch.py"
MARKER = "/app/escape-proof"
VISIBLE_TOKEN = "LUMEN-42"
failures = []

if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("/app/dispatch.py modified or missing (no-modify rule)")


def token_ok(tok):
    return bool(re.fullmatch(r"[A-Za-z0-9\-]+", tok or ""))


def craft_and_consume(mission_path, workdir, token):
    """Run gadget.py on the mission, then the stock consumer on the crafted
    message in a fresh process; return True iff the marker reappears with
    escaped=<token>."""
    try:
        msg = os.path.join(workdir, "msg.pkl")
        if os.path.exists(msg):
            os.remove(msg)
        g = subprocess.run([sys.executable, GADGET, mission_path, msg],
                           capture_output=True, text=True, timeout=60)
        if g.returncode != 0 or not os.path.isfile(msg):
            return False
        if os.path.exists(MARKER):
            os.remove(MARKER)
        d = subprocess.run([sys.executable, CONSUMER, msg],
                           capture_output=True, text=True, timeout=60)
        if d.returncode != 0 or not os.path.isfile(MARKER):
            return False
        with open(MARKER, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
        return content == "escaped=%s\n" % token
    except Exception:
        return False


if not os.path.isfile(GADGET):
    failures.append("missing /app/gadget.py")
else:
    # --- visible-case deliverable: /app/escape-proof (from the agent's run) ---
    try:
        with open(MARKER, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
        if content != "escaped=%s\n" % VISIBLE_TOKEN:
            failures.append("escape-proof content wrong (expected escaped=%s)"
                            % VISIBLE_TOKEN)
    except Exception:
        failures.append("missing /app/escape-proof")

    # --- visible deliverable message must still escape via the consumer ---
    if os.path.isfile("/app/dispatch.msg"):
        try:
            msg_ok = False
            if os.path.exists(MARKER):
                os.remove(MARKER)
            d = subprocess.run([sys.executable, CONSUMER, "/app/dispatch.msg"],
                               capture_output=True, text=True, timeout=60)
            with open(MARKER, "r", encoding="utf-8", errors="replace") as fh:
                content = fh.read()
            msg_ok = d.returncode == 0 and content == "escaped=%s\n" % VISIBLE_TOKEN
            if not msg_ok:
                failures.append("/app/dispatch.msg does not escape via the consumer")
        except Exception:
            failures.append("/app/dispatch.msg unreadable or consumer crashed")
    else:
        failures.append("missing /app/dispatch.msg")

    # --- gadget must generalize: visible mission re-run through gadget.py ---
    work = tempfile.mkdtemp(prefix="vesper_vis_")
    try:
        if not craft_and_consume("/app/mission.txt", work, VISIBLE_TOKEN):
            failures.append("gadget.py failed on the visible mission")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # --- hidden missions: fresh tokens, gadget must not hard-code ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        work = tempfile.mkdtemp(prefix="vesper_hc_")
        try:
            for c in cases:
                mission = os.path.join(hidden_dir, c, "mission.txt")
                exp = os.path.join(hidden_dir, c, "expected.json")
                if not (os.path.isfile(mission) and os.path.isfile(exp)):
                    failures.append("hidden '%s' malformed" % c)
                    continue
                try:
                    with open(exp) as fh:
                        want = json.load(fh)
                    token = str(want["token"])
                except Exception:
                    failures.append("hidden '%s' expected unreadable" % c)
                    continue
                if not token_ok(token):
                    failures.append("hidden '%s' bad token" % c)
                    continue
                mission_copy = os.path.join(work, "mission_%s.txt" % c)
                shutil.copy(mission, mission_copy)
                if not craft_and_consume(mission_copy, work, token):
                    failures.append("hidden case '%s' failed" % c)
                if os.path.exists(MARKER):
                    os.remove(MARKER)
        finally:
            shutil.rmtree(work, ignore_errors=True)
            if os.path.exists(MARKER):
                os.remove(MARKER)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

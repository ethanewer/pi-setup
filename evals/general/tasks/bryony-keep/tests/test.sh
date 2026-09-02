#!/bin/bash
#
# bryony-keep verifier.
# Executes the deliverable /app/configure_lists.py on the visible spec and on
# hidden spec scenarios (different domains, empty member sets, union merges,
# an empty list set, invalid specs that must be rejected with the canonical
# config unchanged), and checks the canonical config via the manager plus the
# visible deliverable /app/report.json. Writes REWARD (0/1) to
# /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

reward=0
if python3 - <<'PY'
import glob, json, os, subprocess, sys

TOOL = "/app/configure_lists.py"
NOTIMGR = "/opt/keepmsg/notimgr.py"
CANONICAL = "/etc/keepmsg/lists.conf"

failures = []


def norm(obj):
    assert isinstance(obj, dict), "report is not a JSON object"
    assert set(obj.keys()) == {"config", "lists"}, sorted(obj.keys())
    assert obj["config"] == CANONICAL, obj["config"]
    lists = obj["lists"]
    assert isinstance(lists, list), lists
    out = []
    for l in lists:
        assert isinstance(l, dict) and set(l.keys()) == {"address", "members"}, l
        out.append((str(l["address"]), tuple(sorted(str(m) for m in l["members"]))))
    return tuple(sorted(out))


def read_manager(label, expect_ok=True):
    try:
        r = subprocess.run([sys.executable, NOTIMGR, "read"],
                           capture_output=True, text=True, timeout=60)
    except Exception as exc:
        failures.append("%s: notimgr crashed (%s)" % (label, exc))
        return None
    if r.returncode != 0:
        if expect_ok:
            failures.append("%s: notimgr read failed (rc=%d)" % (label, r.returncode))
            return None
        return None
    try:
        return norm(json.loads(r.stdout))
    except Exception as exc:
        failures.append("%s: notimgr output unparsable (%s)" % (label, exc))
        return None


def run_tool(spec_path, label):
    try:
        return subprocess.run([sys.executable, TOOL, spec_path],
                              capture_output=True, text=True, timeout=90)
    except Exception as exc:
        failures.append("%s: tool crashed (%s)" % (label, exc))
        return None


# --- infrastructure + deliverables must exist --------------------------------
if not os.path.isfile(NOTIMGR):
    print("verify failures: missing manager control tool %s" % NOTIMGR, file=sys.stderr)
    sys.exit(1)
if not os.path.isfile(TOOL):
    print("verify failures: missing /app/configure_lists.py", file=sys.stderr)
    sys.exit(1)
if not os.path.isfile("/app/report.json"):
    print("verify failures: missing /app/report.json", file=sys.stderr)
    sys.exit(1)

ok = True

# --- visible case: EXECUTE the deliverable on the provided spec --------------
r = run_tool("/app/spec/spec.json", "visible-run")
if r is None:
    ok = False
elif r.returncode != 0:
    failures.append("visible-run: configure_lists.py exited %d" % r.returncode)
    ok = False

want = read_manager("/tests/expected.json")
if want is not None:
    got_live = read_manager("visible-live")
    if got_live != want:
        failures.append("canonical config != visible expected")
        ok = False
    # the committed deliverable /app/report.json must match as well
    try:
        with open("/app/report.json", encoding="utf-8") as fh:
            if norm(json.load(fh)) != want:
                failures.append("report.json does not match visible expected")
                ok = False
    except Exception as exc:
        failures.append("report.json unreadable (%s)" % exc)
        ok = False
    # the config must exist at the canonical path specifically
    if not os.path.isfile(CANONICAL):
        failures.append("canonical config missing at %s" % CANONICAL)
        ok = False
else:
    ok = False

# --- hidden spec scenarios ----------------------------------------------------
cases = 0
for cdir in sorted(glob.glob("/tests/hidden/*/")):
    name = os.path.basename(cdir.rstrip("/"))
    spec = os.path.join(cdir, "spec.json")
    exp = os.path.join(cdir, "expected.json")
    expect_fail = os.path.isfile(os.path.join(cdir, "expect_fail"))
    if not os.path.isfile(spec):
        failures.append("hidden '%s': no spec.json" % name)
        ok = False
        continue
    cases += 1

    if expect_fail:
        before = read_manager("%s:snapshot" % name)
        if before is None:
            failures.append("hidden '%s': cannot snapshot canonical config" % name)
            ok = False
            continue
        r = run_tool(spec, "hidden:%s" % name)
        if r is None:
            ok = False
            continue
        if r.returncode == 0:
            failures.append("hidden '%s': invalid spec accepted (rc=0)" % name)
            ok = False
            continue
        after = read_manager("%s:after" % name)
        if after != before:
            failures.append("hidden '%s': canonical config changed on rejection" % name)
            ok = False
        continue

    if not os.path.isfile(exp):
        failures.append("hidden '%s': no expected.json" % name)
        ok = False
        continue
    r = run_tool(spec, "hidden:%s" % name)
    if r is None:
        ok = False
        continue
    if r.returncode != 0:
        failures.append("hidden '%s': configure_lists.py exited %d" % (name, r.returncode))
        ok = False
        continue
    got = read_manager("hidden:%s" % name)
    try:
        with open(exp, encoding="utf-8") as fh:
            want_h = norm(json.load(fh))
    except Exception as exc:
        failures.append("hidden '%s': expected.json unparsable (%s)" % (name, exc))
        ok = False
        continue
    if got != want_h:
        failures.append("hidden '%s': canonical config != expected" % name)
        ok = False

if cases < 1:
    failures.append("no hidden scenarios")
    ok = False

if failures:
    print("verify failures: %s" % "; ".join(failures), file=sys.stderr)
sys.exit(0 if (ok and not failures) else 1)
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0

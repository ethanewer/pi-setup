#!/bin/bash
# Verifier for ember-quill: guards the no-modify rule on /app/quill.img,
# checks the visible deliverables (/app/recovered + /app/report.json), and
# EXECUTES the deliverable tool (/app/carve.py) on the visible image and on
# every hidden image in /tests/hidden. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_IMG_SHA="2369fef3f45e2c988ea7aa33275b3e0a0f6a11628b2de1089978b4714a02f426"

no_modify_broken=0
if [ ! -f /app/quill.img ]; then
    echo "no-modify: /app/quill.img missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/quill.img | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_IMG_SHA" ]; then
        echo "no-modify: /app/quill.img was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import hashlib, json, os, subprocess, sys, filecmp

TOOL = "/app/carve.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible input /app/quill.img modified or missing")

if not os.path.isfile(TOOL):
    failures.append("missing /app/carve.py")
else:
    def run_recover(img, outdir, report):
        if os.path.exists(outdir):
            import shutil
            shutil.rmtree(outdir)
        if report and os.path.exists(report):
            os.remove(report)
        r = subprocess.run(
            [sys.executable, TOOL, "recover", img, outdir] + ([report] if report else []),
            capture_output=True, text=True, timeout=120,
        )
        return r.returncode == 0

    def dir_matches(got_dir, want_dir):
        if not os.path.isdir(got_dir):
            return False
        got = sorted(os.listdir(got_dir))
        want = sorted(os.listdir(want_dir))
        if got != want:
            return False
        for name in want:
            a = os.path.join(got_dir, name)
            b = os.path.join(want_dir, name)
            if not os.path.isfile(a):
                return False
            with open(a, "rb") as fa, open(b, "rb") as fb:
                if fa.read() != fb.read():
                    return False
        return True

    def load_report(path):
        with open(path) as f:
            rep = json.load(f)
        assert isinstance(rep, dict), rep
        out = {}
        for name, entry in rep.items():
            assert isinstance(entry, dict), entry
            out[name] = {
                "size": int(entry["size"]),
                "version": int(entry["version"]),
                "sha256": str(entry["sha256"]).lower(),
            }
        return out

    # --- visible case: EXECUTE the tool on the live supplied image ---
    if not run_recover("/app/quill.img", "/tmp/quill_vis_out",
                       "/tmp/quill_vis_report.json"):
        failures.append("visible recovery run failed")
    elif not dir_matches("/tmp/quill_vis_out", "/tests/expected"):
        failures.append("visible recovery bytes mismatch")
    elif load_report("/tmp/quill_vis_report.json") != \
            load_report("/tests/expected_report.json"):
        failures.append("visible report mismatch")

    # --- visible deliverables: /app/recovered + /app/report.json ---
    if not dir_matches("/app/recovered", "/tests/expected"):
        failures.append("/app/recovered missing files, has extras, or bytes differ")
    if os.path.isfile("/app/report.json"):
        try:
            if load_report("/app/report.json") != \
                    load_report("/tests/expected_report.json"):
                failures.append("/app/report.json does not match visible expected")
        except Exception:
            failures.append("/app/report.json unreadable")
    else:
        failures.append("missing /app/report.json")

    # --- hidden cases: genuinely distinct images with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            img = os.path.join(base, "img.bin")
            exp_dir = os.path.join(base, "expected")
            exp_rep = os.path.join(base, "expected_report.json")
            if not (os.path.isfile(img) and os.path.isdir(exp_dir)
                    and os.path.isfile(exp_rep)):
                failures.append("hidden '%s' malformed" % c)
                continue
            outdir = "/tmp/quill_hid_%s_out" % c
            rep = "/tmp/quill_hid_%s_report.json" % c
            if not run_recover(img, outdir, rep):
                failures.append("hidden '%s': recovery run failed" % c)
                continue
            if not dir_matches(outdir, exp_dir):
                failures.append("hidden '%s': recovered bytes mismatch" % c)
            elif load_report(rep) != load_report(exp_rep):
                failures.append("hidden '%s': report mismatch" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

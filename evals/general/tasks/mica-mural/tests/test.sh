#!/bin/bash
# Verifier for mica-mural (executes-deliverable).
#
# Checks the three deliverables, enforces both size gates and the
# no-embedding rule, EXECUTES /app/mural.py on the shipped spec and on every
# hidden spec in /tests/hidden, comparing output byte-for-byte against the
# documented contract (recomputed independently by the verifier).
# Writes reward (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import gzip
import json
import os
import subprocess
import sys

RENDER = "/app/mural.py"
RAW_CAP = 800
GZIP_CAP = 320
failures = []


def expected_frame(spec):
    w, h, p = spec["width"], spec["height"], spec["palette"]
    c0, c1, c2, c3, c4, c5 = spec["coef"]
    m3, m4 = spec["mods"]
    P = len(p)
    lines = []
    for y in range(h):
        lines.append("".join(
            p[(c0 * x + c1 * y + c2 * x * y + c3 * (x * x % m3)
               + c4 * (y * y % m4) + c5) % P]
            for x in range(w)))
    return ("\n".join(lines) + "\n").encode("utf-8")


def run_case(spec_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run([sys.executable, RENDER, spec_path, out_path],
                           capture_output=True, text=True, timeout=60)
    except Exception as e:
        failures.append("render failed on %s: %r" % (spec_path, e))
        return None
    if r.returncode != 0:
        failures.append("render exited %d on %s" % (r.returncode, spec_path))
        return None
    if not os.path.exists(out_path):
        failures.append("no output for %s" % spec_path)
        return None
    try:
        return open(out_path, "rb").read()
    except OSError as e:
        failures.append("unreadable output for %s: %r" % (spec_path, e))
        return None


# ---- source gates (raw size, gzip size, no-embedding) -----------------------
src_bytes = b""
try:
    src_bytes = open(RENDER, "rb").read()
except OSError:
    failures.append("missing /app/mural.py")
src_text = None
if src_bytes:
    if len(src_bytes) > RAW_CAP:
        failures.append("raw source %d > %d" % (len(src_bytes), RAW_CAP))
    gz = len(gzip.compress(src_bytes))
    if gz > GZIP_CAP:
        failures.append("gzip source %d > %d" % (gz, GZIP_CAP))
    try:
        src_text = src_bytes.decode("utf-8", errors="replace")
    except Exception:
        src_text = None

# ---- sizes report must match reality ---------------------------------------
try:
    with open("/app/mural-sizes.json") as fh:
        rep = json.load(fh)
    assert isinstance(rep, dict)
    assert set(rep.keys()) == {"source_bytes", "gzip_bytes"}, rep.keys()
    if src_bytes:
        assert rep["source_bytes"] == len(src_bytes), "stale source_bytes"
        assert rep["gzip_bytes"] == len(gzip.compress(src_bytes)), "stale gzip_bytes"
except Exception as e:
    failures.append("mural-sizes.json bad or mismatched: %r" % e)

# ---- visible case: run the deliverable, compare bytes, check embedding -----
vis_spec = "/app/spec.json"
vis_out = "/tmp/mica_mural_vis.txt"
got = run_case(vis_spec, vis_out)
vis_palette = None
if got is not None:
    try:
        with open(vis_spec) as fh:
            spec = json.load(fh)
        vis_palette = spec["palette"]
        want = expected_frame(spec)
        if got != want:
            failures.append("visible frame mismatch")
        # no-embedding: no full output line of the mural in the source
        # (uniform single-character lines are exempt: they carry no layout
        # information and could coincide with source whitespace)
        if src_text is not None:
            for line in want.decode("utf-8").splitlines():
                if (len(line) >= 8 and len(set(line)) >= 2
                        and line in src_text):
                    failures.append("output line embedded in source")
                    break
            if len(vis_palette) >= 8 and vis_palette in src_text:
                failures.append("palette literal embedded in source")
    except Exception as e:
        failures.append("visible case error: %r" % e)
# the /app/frame.txt deliverable must match the same contract
try:
    with open("/app/frame.txt", "rb") as fh:
        frame_txt = fh.read()
    with open(vis_spec) as fh:
        if frame_txt != expected_frame(json.load(fh)):
            failures.append("/app/frame.txt mismatch")
except Exception as e:
    failures.append("/app/frame.txt unreadable or wrong: %r" % e)

# ---- hidden cases -----------------------------------------------------------
hidden = "/tests/hidden"
if not os.path.isdir(hidden) or not any(os.scandir(hidden)):
    failures.append("no hidden cases")
else:
    for name in sorted(os.listdir(hidden)):
        base = os.path.join(hidden, name)
        sp = os.path.join(base, "spec.json")
        if not os.path.isfile(sp):
            failures.append("hidden '%s': missing spec.json" % name)
            continue
        try:
            with open(sp) as fh:
                spec = json.load(fh)
        except Exception as e:
            failures.append("hidden '%s': bad spec: %r" % (name, e))
            continue
        got = run_case(sp, "/tmp/mica_mural_hidden.txt")
        if got is None:
            continue
        try:
            want = expected_frame(spec)
            if got != want:
                failures.append("hidden '%s': frame mismatch" % name)
            if src_text is not None:
                pal = spec["palette"]
                if len(pal) >= 8 and pal in src_text:
                    failures.append("hidden '%s': palette embedded" % name)
        except Exception as e:
            failures.append("hidden '%s': check error: %r" % (name, e))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

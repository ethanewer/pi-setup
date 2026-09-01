#!/bin/bash
# Verifier for lichen-mesa: checks the visible-case deliverables, ENFORCES the
# no-modify rule on /app/survey, and EXECUTES the deliverable program
# (/app/survey.py) on the visible tile and on every hidden tile under
# /tests/hidden. Writes 0/1 to /logs/verifier/reward.txt. Never crashes on
# malformed/missing agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the visible tile fixtures (instruction forbids modifying
# /app/survey/; tampering would defeat the visible-case check).
tile_dir=/app/survey/tile_alpha
no_modify_broken=0
for f in scene.png sam_model.py sam_weights.pt prompts.csv; do
    if [ ! -f "$tile_dir/$f" ]; then
        echo "no-modify: $tile_dir/$f missing" >&2
        no_modify_broken=1
    fi
done
if [ "$no_modify_broken" = "0" ]; then
    a="$(sha256sum "$tile_dir/scene.png" | awk '{print $1}')"
    b="$(sha256sum "$tile_dir/prompts.csv" | awk '{print $1}')"
    ca="$(sha256sum /tests/expected_visible/scene.png.sha 2>/dev/null | awk '{print $1}')"
    if [ "$a" != "$(cat /tests/expected_visible/scene.png.sha 2>/dev/null)" ] \
       || [ "$b" != "$(cat /tests/expected_visible/prompts.csv.sha 2>/dev/null)" ]; then
        echo "no-modify: visible tile fixtures were modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import csv, json, os, subprocess, sys

SURVEY = "/app/survey.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("visible tile modified or missing (no-modify rule)")


def load_cells(path):
    with open(path, newline="") as fh:
        rdr = csv.reader(fh)
        rows = list(rdr)
    assert rows, "empty csv"
    assert rows[0] == ["cell_id", "area", "cx", "cy", "bx0", "by0", "bx1", "by1"], rows[0]
    out = []
    for r in rows[1:]:
        assert len(r) == 8, r
        out.append((r[0], int(r[1]), float(r[2]), float(r[3]),
                    int(r[4]), int(r[5]), int(r[6]), int(r[7])))
    return out


def compare(out_dir, exp_dir, label):
    try:
        # masks.npz: identical key set and identical 0/1 uint8 arrays
        got = np_load(os.path.join(out_dir, "masks.npz"))
        want = np_load(os.path.join(exp_dir, "masks.npz"))
        if sorted(got.keys()) != sorted(want.keys()):
            return "masks.npz key mismatch"
        for k in want.keys():
            a, b = got[k], want[k]
            if a.shape != b.shape or a.dtype != b.dtype:
                return "mask %s shape/dtype mismatch" % k
            if not (a.astype("int64") == b.astype("int64")).all():
                return "mask %s values differ" % k
        # cells.csv
        gc = load_cells(os.path.join(out_dir, "cells.csv"))
        wc = load_cells(os.path.join(exp_dir, "cells.csv"))
        if len(gc) != len(wc):
            return "cells.csv row count differs"
        for g, w in zip(gc, wc):
            if g[0] != w[0]:
                return "cells.csv cell_id order differs"
            if g[1] != w[1] or any(g[i] != w[i] for i in range(4, 8)):
                return "cells.csv numeric fields differ for %s" % g[0]
            if abs(g[2] - w[2]) > 1e-6 or abs(g[3] - w[3]) > 1e-6:
                return "cells.csv centroid differs for %s" % g[0]
        # analysis.json
        with open(os.path.join(out_dir, "analysis.json")) as fh:
            ga = json.load(fh)
        with open(os.path.join(exp_dir, "analysis.json")) as fh:
            wa = json.load(fh)
        if not isinstance(ga, dict) or set(ga) != {"tile", "n_cells", "empty_cells", "foreground_pixels"}:
            return "analysis.json keys wrong"
        for k in ("n_cells", "empty_cells", "foreground_pixels"):
            if ga[k] != wa[k]:
                return "analysis.json %s differs" % k
        if ga["tile"] != wa["tile"]:
            return "analysis.json tile name differs"
        return None
    except Exception as e:
        return "%s: malformed output (%s)" % (label, e)


def np_load(path):
    import numpy as np
    with np.load(path) as z:
        return {k: z[k].copy() for k in z.files}


def run_case(tile, out_dir, exp_dir, label):
    import shutil
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    try:
        r = subprocess.run([sys.executable, SURVEY, tile, out_dir],
                           capture_output=True, text=True, timeout=240)
    except Exception as e:
        failures.append("%s: survey.py failed to run (%s)" % (label, e))
        return
    if r.returncode != 0:
        failures.append("%s: survey.py exited %d" % (label, r.returncode))
        return
    err = compare(out_dir, exp_dir, label)
    if err:
        failures.append("%s: %s" % (label, err))


if not os.path.isfile(SURVEY):
    failures.append("missing /app/survey.py")
else:
    # visible tile: execute the deliverable
    run_case("/app/survey/tile_alpha", "/tmp/lm_vis", "/tests/expected_visible", "visible")
    # visible-case answer bundle must exist and match
    if os.path.isdir("/app/answer") and \
            all(os.path.isfile(os.path.join("/app/answer", f))
                for f in ("masks.npz", "cells.csv", "analysis.json")):
        err = compare("/app/answer", "/tests/expected_visible", "answer")
        if err:
            failures.append("answer bundle: %s" % err)
    else:
        failures.append("missing /app/answer bundle artifacts")

    hidden = "/tests/hidden"
    if os.path.isdir(hidden):
        cases = sorted(d for d in os.listdir(hidden)
                       if os.path.isdir(os.path.join(hidden, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            tile = os.path.join(hidden, c, "tile")
            exp = os.path.join(hidden, c, "expected")
            if not (os.path.isdir(tile) and os.path.isdir(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            run_case(tile, "/tmp/lm_h_" + c, exp, "hidden/" + c)
    else:
        failures.append("no hidden cases")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

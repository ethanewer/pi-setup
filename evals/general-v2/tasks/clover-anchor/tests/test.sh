#!/bin/bash
# Verifier for clover-anchor: enforces the no-modify rule on the supplied /app
# data, loads and validates /app/model.pkl against an independently recomputed
# reference, and EXECUTES /app/fit.py on every hidden CSV, validating each
# produced pickle. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_CSV_SHA="934863462e544335efd3d712cc72913fc0e82221c67003c63c399f18cfe94300"

no_modify_broken=0
if [ ! -f /app/data/zone_readings.csv ]; then
    echo "no-modify: /app/data/zone_readings.csv missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/data/zone_readings.csv | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_CSV_SHA" ]; then
        echo "no-modify: /app/data/zone_readings.csv was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import csv, os, pickle, subprocess, sys

SOLVE = "/app/fit.py"
no_modify_broken = int(sys.argv[1])


def reference(csv_path):
    """Independently recompute the fitted dict from a CSV."""
    feats = {}
    n = 0
    with open(csv_path, newline="") as fh:
        for row in csv.DictReader(fh):
            zone = row["zone"].strip()
            vec = [float(row["temp_c"]), float(row["humidity_pct"]),
                   float(row["light_lux"])]
            feats.setdefault(zone, []).append(vec)
            n += 1
    classes = sorted(feats)
    centroids = {z: [sum(c) / len(c) for c in zip(*feats[z])] for z in classes}
    return {
        "model": "nearest-centroid",
        "fitted": True,
        "n_features": 3,
        "n_samples": n,
        "classes": classes,
        "centroids": centroids,
    }


def check_pkl(pkl_path, csv_path, failures, tag):
    try:
        with open(pkl_path, "rb") as fh:
            got = pickle.load(fh)
    except Exception as e:
        failures.append("%s: pickle unreadable (%r)" % (tag, e))
        return
    try:
        want = reference(csv_path)
        assert isinstance(got, dict), "not a dict"
        assert set(got.keys()) == set(want.keys()), sorted(got.keys())
        assert got["model"] == want["model"], got["model"]
        assert got["fitted"] is True, "fitted flag not True"
        assert int(got["n_features"]) == want["n_features"]
        assert int(got["n_samples"]) == want["n_samples"]
        assert list(got["classes"]) == want["classes"], got["classes"]
        assert set(got["centroids"].keys()) == set(want["centroids"].keys())
        for z, vec in want["centroids"].items():
            gotv = got["centroids"][z]
            assert isinstance(gotv, list) and len(gotv) == 3, gotv
            for g, w in zip(gotv, vec):
                assert abs(float(g) - w) <= 1e-9, (z, gotv, vec)
    except Exception as e:
        failures.append("%s: wrong content (%r)" % (tag, e))


failures = []
if no_modify_broken:
    failures.append("visible data modified or missing (no-modify rule)")

if not os.path.isfile("/app/fit.py"):
    failures.append("missing /app/fit.py")
else:
    # visible-case deliverable: /app/model.pkl exists and matches a reference
    # recomputed from the pristine visible CSV
    if os.path.isfile("/app/model.pkl"):
        check_pkl("/app/model.pkl", "/app/data/zone_readings.csv",
                  failures, "model.pkl")
    else:
        failures.append("missing /app/model.pkl")

    # hidden cases: run the deliverable program on fresh CSVs
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        out = "/tmp/clover_anchor_verify_out.pkl"
        for c in cases:
            data = os.path.join(hidden_dir, c, "data.csv")
            if not os.path.isfile(data):
                failures.append("hidden '%s' malformed" % c)
                continue
            if os.path.exists(out):
                os.remove(out)
            try:
                r = subprocess.run(
                    [sys.executable, "/app/fit.py", data, out],
                    capture_output=True, text=True, timeout=120,
                )
                if r.returncode != 0 or not os.path.exists(out):
                    failures.append("hidden '%s': fit.py failed" % c)
                    continue
                check_pkl(out, data, failures, "hidden '%s'" % c)
            except Exception as e:
                failures.append("hidden '%s': error %r" % (c, e))
    else:
        failures.append("no hidden case directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

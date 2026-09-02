#!/bin/bash
# Verifier for coral-trellis: checks the visible-case deliverables are present
# and correct, ENFORCES the no-modify rule on the supplied /app fixtures, and
# EXECUTES the deliverable program (/app/solver.py) on the visible case and on
# every hidden case in /tests/hidden, comparing the recovered directed edge SET
# exactly. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (the instruction tells the
# agent not to modify these; tampering defeats the visible-case check).
PRISTINE_TELEMETRY_SHA="b736e7a4acd1f254134d2024251e925d844297e6149a7e9af89e098a702d2c41"
PRISTINE_SPEC_SHA="3b82f819a66bbc95f0d92501ed6f9dcfef31736c49d88a5edff662d32bd9daa8"

no_modify_broken=0
check_pristine() {
    local path="$1" want="$2" label="$3"
    if [ ! -f "$path" ]; then
        echo "no-modify: $label missing" >&2
        no_modify_broken=1
        return
    fi
    local actual
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $label was modified" >&2
        no_modify_broken=1
    fi
}
check_pristine /app/telemetry.csv "$PRISTINE_TELEMETRY_SHA" /app/telemetry.csv
check_pristine /app/spec.json "$PRISTINE_SPEC_SHA" /app/spec.json

python3 - "$no_modify_broken" <<'PY'
import csv, json, os, subprocess, sys, tempfile

SOLVER = "/app/solver.py"
no_modify_broken = int(sys.argv[1])
failures = []


def read_edges(path):
    """Read a recovered_edges.csv; returns frozenset of 'parent,child' strings."""
    edges = set()
    with open(path, "r", newline="") as fh:
        rd = csv.reader(fh)
        header = next(rd)
        assert header == ["parent", "child"], header
        for row in rd:
            if not row:
                continue
            assert len(row) == 2, row
            p, c = row[0].strip(), row[1].strip()
            assert p and c, row
            edges.add("%s,%s" % (p, c))
    return frozenset(edges)


def read_expected(path):
    with open(path) as fh:
        obj = json.load(fh)
    edges = obj["edges"]
    assert isinstance(edges, list) and edges
    for e in edges:
        p, c = e.split(",")
        assert p and c
    return frozenset(edges), int(obj["edge_count"])


def run_solver(data, spec, outdir):
    if os.path.isdir(outdir):
        for f in os.listdir(outdir):
            os.remove(os.path.join(outdir, f))
    else:
        os.makedirs(outdir, exist_ok=True)
    r = subprocess.run(
        [sys.executable, SOLVER, data, spec, outdir],
        capture_output=True, text=True, timeout=240,
    )
    out = os.path.join(outdir, "recovered_edges.csv")
    if r.returncode != 0 or not os.path.isfile(out):
        return None
    try:
        return read_edges(out)
    except Exception as exc:
        failures.append("unparseable output: %r" % exc)
        return None


def check_case(tag, data, spec, expected_path):
    if not all(os.path.isfile(p) for p in (data, spec, expected_path)):
        failures.append("%s: missing input/expected files" % tag)
        return
    try:
        want, want_n = read_expected(expected_path)
    except Exception as exc:
        failures.append("%s: bad expected fixture: %r" % (tag, exc))
        return
    got = run_solver(data, spec, tempfile.mkdtemp(prefix="ct_verify_"))
    if got is None:
        failures.append("%s: solver did not run / produced no output" % tag)
        return
    if len(got) != want_n:
        failures.append("%s: expected %d edges, got %d" % (tag, want_n, len(got)))
    if got != want:
        failures.append("%s: recovered edge set mismatch" % tag)


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVER):
    failures.append("missing /app/solver.py")
else:
    # visible case: execute the solver on the live fixtures
    check_case("visible", "/app/telemetry.csv", "/app/spec.json",
               "/tests/expected.json")
    # visible-case deliverable /app/recovered_edges.csv must match too
    if os.path.isfile("/app/recovered_edges.csv"):
        try:
            got = read_edges("/app/recovered_edges.csv")
            want, _ = read_expected("/tests/expected.json")
            if got != want:
                failures.append("/app/recovered_edges.csv mismatch vs visible expected")
        except Exception as exc:
            failures.append("/app/recovered_edges.csv unreadable: %r" % exc)
    else:
        failures.append("missing /app/recovered_edges.csv")

    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        base = os.path.join(hidden_dir, c)
        check_case("hidden:%s" % c,
                   os.path.join(base, "data.csv"),
                   os.path.join(base, "spec.json"),
                   os.path.join(base, "expected.json"))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

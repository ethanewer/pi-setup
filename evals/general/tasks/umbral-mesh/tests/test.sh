#!/bin/bash
# umbral-mesh verifier. Checks the visible-case deliverables, enforces the
# no-modify rule on the supplied /app fixtures, and EXECUTES /app/solve.py on
# the visible case and on every hidden case under /tests/hidden. Writes
# /logs/verifier/reward.txt (1.0 or 0.0). Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures (the instruction forbids
# modifying them; tampering defeats the visible-case check).
PRISTINE_TELEMETRY_SHA="b5e215b9c59a01323549661ca7bb9934fcd5aa83e4f0321f4e43dea5e7158ea3"
PRISTINE_SPEC_SHA="6ec8cced51e197be9f98c5266437af5d1025e8339e1899595b7950209647ef5f"

no_modify_broken=0
for pair in "/app/telemetry.csv:$PRISTINE_TELEMETRY_SHA" "/app/spec.json:$PRISTINE_SPEC_SHA"; do
  path="${pair%%:*}"
  want="${pair#*:}"
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

python3 - "$no_modify_broken" <<'PY'
import csv, json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []


def norm_edges(path):
    """Parse an edges CSV into a normalized structure; raise on malformed input."""
    with open(path, "r", encoding="utf-8", newline="") as fh:
        rows = list(csv.reader(fh))
    if not rows:
        raise ValueError("empty csv")
    header = [c.strip() for c in rows[0]]
    if header != ["parent", "child"]:
        raise ValueError("bad header %r" % (header,))
    edges = set()
    for row in rows[1:]:
        if len(row) != 2:
            raise ValueError("bad row %r" % (row,))
        p, c = row[0].strip(), row[1].strip()
        if not p or not c:
            raise ValueError("empty endpoint")
        edges.add((p, c))
    return edges, len(rows) - 1


def run_case(telemetry, spec, expected_path):
    out = "/tmp/umbral_mesh_verify_out.csv"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, telemetry, spec, out],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("solver crashed: %r" % (exc,))
        return False
    if r.returncode != 0 or not os.path.exists(out):
        failures.append("solver exit=%d out_exists=%s" % (r.returncode, os.path.exists(out)))
        return False
    try:
        got_edges, got_n = norm_edges(out)
        want_edges, want_n = norm_edges(expected_path)
    except Exception as exc:
        failures.append("unparseable edges csv: %r" % (exc,))
        return False
    if got_edges != want_edges:
        failures.append("edge set mismatch: missing=%s extra=%s"
                        % (sorted(want_edges - got_edges), sorted(got_edges - want_edges)))
        return False
    if got_n != want_n:
        failures.append("row count %d != expected %d" % (got_n, want_n))
        return False
    return True


if no_modify_broken:
    failures.append("visible inputs modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # visible case: EXECUTE the deliverable solver on the live fixtures
    if not (os.path.isfile("/app/telemetry.csv") and os.path.isfile("/app/spec.json")):
        failures.append("visible fixtures missing")
    elif not run_case("/app/telemetry.csv", "/app/spec.json", "/tests/expected_visible.csv"):
        pass  # run_case already recorded the reason

    # visible-case deliverable: /app/recovered_edges.csv must exist and match
    if os.path.isfile("/app/recovered_edges.csv"):
        try:
            got_edges, _ = norm_edges("/app/recovered_edges.csv")
            want_edges, _ = norm_edges("/tests/expected_visible.csv")
            if got_edges != want_edges:
                failures.append("recovered_edges.csv does not match visible expected")
        except Exception as exc:
            failures.append("recovered_edges.csv unparseable: %r" % (exc,))
    else:
        failures.append("missing /app/recovered_edges.csv")

    # hidden cases: genuinely distinct telemetry/spec pairs
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            tele = os.path.join(base, "telemetry.csv")
            spec = os.path.join(base, "spec.json")
            exp = os.path.join(base, "expected_edges.csv")
            if not all(os.path.isfile(p) for p in (tele, spec, exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            run_case(tele, spec, exp)
    else:
        failures.append("no hidden cases dir")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0

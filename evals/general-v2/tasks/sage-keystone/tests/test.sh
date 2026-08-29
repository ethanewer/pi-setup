#!/bin/bash
# Verifier for tasks/sage-keystone (executes-deliverable).
#
# Executes every runnable deliverable and checks behavior:
#   * /app/extract_fields.py -- re-run on the visible sample and on three hidden
#     forms (labelled, a field with NO /TU, and a control-less document); must
#     match an independent pypdf reading of the same PDFs; /app/form_fields.json
#     must equal the visible extraction.
#   * /app/query.rq -- executed via rdflib against the visible ledger and two
#     hidden ledgers (decoys: unnamed recruit, un-typed seconded entity, firm
#     with no name, duplicate secondments) and must project ?recruit and ?firm
#     correctly; /app/results.csv must match the visible reference.
#   * /app/decode_mesh.py -- run against the visible rig and three hidden SKM1
#     files (multi-bone, sparse, zero-bone) and must equal an independent
#     struct/numpy read of the same binaries; a torn file must exit non-zero.
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

for path in /app/extract_fields.py /app/form_fields.json \
            /app/query.rq /app/results.csv \
            /app/decode_mesh.py /app/mesh_arrays.npz; do
  if [ ! -f "$path" ]; then
    echo "missing deliverable $path" >&2
    echo "0" > /logs/verifier/reward.txt
    exit 0
  fi
done

python3 - <<'PYEOF'
import json
import os
import struct
import subprocess
import sys

import numpy as np
from pypdf import PdfReader
from rdflib import Graph

failures = []
HALL = "/tests/hidden"


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


# ---------------------------------------------------------------------------
# Reference SPARQL (independent known-good semantics) and a runner that returns
# the result rows keyed by their variable NAME.
# ---------------------------------------------------------------------------
REF_QUERY = """PREFIX kbs: <http://keystone.sage.example/schema#>
SELECT DISTINCT ?recruit ?firm WHERE {
  ?r a kbs:Recruit ;
     kbs:name ?recruit ;
     kbs:secondedTo ?f .
  ?f kbs:name ?firm .
}
"""


def run_query(graph_path, query_text):
    try:
        g = Graph()
        g.parse(graph_path, format="turtle")
        res = g.query(query_text)
        varnames = {str(v).lstrip("?"): i for i, v in enumerate(res.vars)}
        if set(varnames) != {"recruit", "firm"}:
            return None, "SELECT vars are %s, want exactly {recruit, firm}" % \
                         sorted(varnames)
        rows = sorted((str(row[varnames["recruit"]]), str(row[varnames["firm"]]))
                      for row in res)
        return rows, None
    except Exception as exc:
        return None, "query failed: %r" % exc


# ---------------------------------------------------------------------------
# Independent struct/numpy decoder of the documented SKM1 layout.
# ---------------------------------------------------------------------------
def ref_decode(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"SKM1":
        raise ValueError("bad magic")
    n_v, n_b, k_inf, _ = struct.unpack_from("<IIII", data, 4)
    off = 20
    positions = np.empty((n_v, 3), np.float32)
    normals = np.empty((n_v, 3), np.float32)
    texcoords = np.empty((n_v, 2), np.float32)
    weights = np.empty((n_v, k_inf), np.float32)
    bones = np.empty((n_v, k_inf), np.int32)
    for i in range(n_v):  # interleaved per-vertex layout (row-major records)
        positions[i] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        normals[i] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        texcoords[i] = np.frombuffer(data[off:off + 8], np.float32); off += 8
        weights[i] = np.frombuffer(data[off:off + 4 * k_inf], np.float32); off += 4 * k_inf
        bones[i] = np.frombuffer(data[off:off + 4 * k_inf], np.int32); off += 4 * k_inf
    out = {"positions": positions, "normals": normals, "texcoords": texcoords,
           "weights": weights, "bones": bones}
    bp = np.empty((n_b, 3), np.float32)
    br = np.empty((n_b, 4), np.float32)
    pa = np.empty(n_b, np.int32)
    for b in range(n_b):
        bp[b] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        br[b] = np.frombuffer(data[off:off + 16], np.float32); off += 16
        pa[b] = struct.unpack_from("<i", data, off)[0]; off += 4
    out["bind_positions"] = bp
    out["bind_rotations"] = br
    out["parents"] = pa
    return out


WANT = ["positions", "normals", "texcoords", "weights", "bones",
        "bind_positions", "bind_rotations", "parents"]


def compare_np(npz_path, expected):
    if not os.path.exists(npz_path):
        return "missing npz"
    try:
        z = np.load(npz_path)
    except Exception as exc:
        return "npz unreadable: %r" % exc
    if sorted(z.files) != sorted(WANT):
        return "keys %s != %s" % (sorted(z.files), sorted(WANT))
    for k in WANT:
        got = np.asarray(z[k])
        exp = expected[k]
        if got.shape != exp.shape:
            return "%s shape %s != %s" % (k, got.shape, exp.shape)
        if not np.array_equal(got, exp):
            return "%s values differ" % k
    return None


# ---------------------------------------------------------------------------
# A. PDF field extraction (visible + hidden).
# ---------------------------------------------------------------------------
def expected_fields(path):
    reader = PdfReader(path)
    fields = reader.get_fields() or {}
    return [(k, (v.get("/TU") or "") if isinstance(v, dict) else "")
            for k, v in fields.items()]


def check_extract(label, pdf):
    out = run(["python3", "/app/extract_fields.py", pdf])
    if out.returncode != 0:
        failures.append("%s: exit rc=%d %s"
                        % (label, out.returncode, (out.stderr or "")[-200:]))
        return
    try:
        got = [(str(o["id"]), str(o.get("label", ""))) for o in json.loads(out.stdout)]
    except Exception as exc:
        failures.append("%s: bad JSON output: %r" % (label, exc))
        return
    expect = [(k, v) for k, v in expected_fields(pdf)]
    if got != expect:
        failures.append("%s: got %r != expected %r" % (label, got, expect))


check_extract("visible form", "/app/permit_form.pdf")
check_extract("hidden form A", os.path.join(HALL, "forms", "hid_a.pdf"))
check_extract("hidden form B (no label)", os.path.join(HALL, "forms", "hid_b.pdf"))
check_extract("hidden form C (no fields)", os.path.join(HALL, "forms", "hid_c.pdf"))

if os.path.exists("/app/form_fields.json"):
    try:
        with open("/app/form_fields.json") as fh:
            got = [(str(o["id"]), str(o.get("label", "")))
                   for o in json.load(fh)]
        expect = [(k, v) for k, v in expected_fields("/app/permit_form.pdf")]
        if got != expect:
            failures.append("form_fields.json != visible extraction: %r != %r"
                            % (got, expect))
    except Exception as exc:
        failures.append("form_fields.json unreadable/malformed: %r" % exc)

# ---------------------------------------------------------------------------
# B. SPARQL: visible results.csv + visible and hidden query.rq generalization.
# ---------------------------------------------------------------------------
QUERY = open("/app/query.rq").read()

exp_vis, we = run_query("/app/registry.ttl", REF_QUERY)
got_vis, ge = run_query("/app/registry.ttl", QUERY)
if we or ge:
    failures.append("SPARQL visible: want_err=%s got_err=%s" % (we, ge))
elif got_vis != exp_vis:
    failures.append("query.rq on visible ledger differs from reference: %r != %r"
                    % (got_vis, exp_vis))

if os.path.exists("/app/results.csv"):
    lines = open("/app/results.csv").read().splitlines()
    if not lines or lines[0] != "recruit,firm":
        failures.append("results.csv header wrong: %r" % (lines[:1],))
    else:
        got = sorted(tuple(ln.split(",")) for ln in lines[1:] if ln != "")
        if exp_vis is not None and got != exp_vis:
            failures.append("results.csv rows %r != expected %r" % (got, exp_vis))
else:
    failures.append("results.csv missing")

for name in ("g1.ttl", "g2.ttl"):
    hp = os.path.join(HALL, "sparql", name)
    want, werr = run_query(hp, REF_QUERY)
    got, gerr = run_query(hp, QUERY)
    if werr or gerr:
        failures.append("%s: want_err=%s got_err=%s" % (name, werr, gerr))
    elif got != want:
        failures.append("%s: query.rq rows %r != %r" % (name, got, want))

# ---------------------------------------------------------------------------
# C. SKM1 mesh decode: visible, hidden valid, hidden malformed.
# ---------------------------------------------------------------------------
def check_decode(bin_path, label, expect_bad=False):
    out = run(["python3", "/app/decode_mesh.py", bin_path, "/tmp/_dec.npz"])
    if expect_bad:
        if out.returncode == 0:
            failures.append("%s: accepted malformed input, rc=0" % label)
        elif not out.stderr.strip():
            failures.append("%s: malformed rejected but no stderr message" % label)
        return
    if out.returncode != 0:
        failures.append("%s: decode failed rc=%d %s"
                        % (label, out.returncode, (out.stderr or "")[-300:]))
        return
    try:
        expected = ref_decode(bin_path)
    except Exception as exc:
        failures.append("%s: ref read fail: %r" % (label, exc))
        return
    err = compare_np("/tmp/_dec.npz", expected)
    if err:
        failures.append("%s: %s" % (label, err))


check_decode("/app/hull_rig.bin", "visible hull")
check_decode(os.path.join(HALL, "mesh", "hid_a.bin"), "hidden mesh A")
check_decode(os.path.join(HALL, "mesh", "hid_b.bin"), "hidden mesh B (skin)")
check_decode(os.path.join(HALL, "mesh", "hid_c.bin"), "hidden mesh C (no bones)")
check_decode(os.path.join(HALL, "mesh", "hid_bad.bin"), "hidden mesh (torn)",
             expect_bad=True)

if os.path.exists("/app/mesh_arrays.npz"):
    try:
        err = compare_np("/app/mesh_arrays.npz", ref_decode("/app/hull_rig.bin"))
        if err:
            failures.append("mesh_arrays.npz: %s" % err)
    except Exception as exc:
        failures.append("mesh_arrays.npz ref read fail: %r" % exc)

if failures:
    print("FAILURES:")
    for m in failures:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PYEOF
#!/bin/bash
# Oracle for tasks/sage-keystone. Writes the three runnable deliverables into
# /app (the real work), then RUNS them to produce the derived outputs. Never
# reads /tests.
set -eu

# ------------------------------------------------------------------ /app/extract_fields.py
cat > /app/extract_fields.py <<'PY'
#!/usr/bin/env python3
"""Enumerate interactive AcroForm fields from a PDF and print a JSON array."""
import sys
import json
from pypdf import PdfReader


def main():
    pdf = sys.argv[1]
    reader = PdfReader(pdf)
    fields = reader.get_fields() or {}
    out = []
    for key in fields:
        fd = fields[key]
        label = fd.get("/TU")
        if not isinstance(label, str):
            label = ""
        out.append({"id": key, "label": label})
    sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    main()
PY

# ------------------------------------------------------------------------- /app/query.rq
cat > /app/query.rq <<'SPARQL'
PREFIX kbs: <http://keystone.sage.example/schema#>
SELECT DISTINCT ?recruit ?firm
WHERE {
  ?r a kbs:Recruit ;
     kbs:name ?recruit ;
     kbs:secondedTo ?f .
  ?f kbs:name ?firm .
}
SPARQL

# ------------------------------------------------------------------------- /app/decode_mesh.py
cat > /app/decode_mesh.py <<'PY'
#!/usr/bin/env python3
"""Decode a SKM1 skinned-mesh binary into a numpy zip archive, or fail cleanly."""
import sys
import struct
import numpy as np

MAGIC = b"SKM1"


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("ERROR: usage: decode_mesh.py <BIN> <NPZ>\n")
        return 1
    src, dst = sys.argv[1], sys.argv[2]
    try:
        with open(src, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        sys.stderr.write("ERROR: cannot read: %s\n" % exc)
        return 1

    if len(data) < 20:
        sys.stderr.write("ERROR: truncated header\n")
        return 1
    if data[:4] != MAGIC:
        sys.stderr.write("ERROR: bad magic\n")
        return 1

    n_v, n_b, k_inf, _res = struct.unpack_from("<IIII", data, 4)
    if k_inf > 64:
        sys.stderr.write("ERROR: implausible influence count\n")
        return 1

    v_rec = 12 + 12 + 8 + 4 * k_inf + 4 * k_inf
    b_rec = 12 + 16 + 4
    expected = 20 + n_v * v_rec + n_b * b_rec
    if expected != len(data):
        sys.stderr.write("ERROR: length mismatch\n")
        return 1

    off = 20
    positions = np.empty((n_v, 3), np.float32)
    normals = np.empty((n_v, 3), np.float32)
    texcoords = np.empty((n_v, 2), np.float32)
    weights = np.empty((n_v, k_inf), np.float32)
    bones = np.empty((n_v, k_inf), np.int32)

    for i in range(n_v):
        positions[i] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        normals[i] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        texcoords[i] = np.frombuffer(data[off:off + 8], np.float32); off += 8
        weights[i] = np.frombuffer(data[off:off + 4 * k_inf], np.float32); off += 4 * k_inf
        bones[i] = np.frombuffer(data[off:off + 4 * k_inf], np.int32); off += 4 * k_inf

    bind_pos = np.empty((n_b, 3), np.float32)
    bind_rot = np.empty((n_b, 4), np.float32)
    parents = np.empty(n_b, np.int32)
    for b in range(n_b):
        bind_pos[b] = np.frombuffer(data[off:off + 12], np.float32); off += 12
        bind_rot[b] = np.frombuffer(data[off:off + 16], np.float32); off += 16
        parents[b] = struct.unpack_from("<i", data, off)[0]; off += 4

    np.savez(dst, positions=positions, normals=normals, texcoords=texcoords,
             weights=weights, bones=bones, bind_positions=bind_pos,
             bind_rotations=bind_rot, parents=parents)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x /app/extract_fields.py /app/decode_mesh.py

# ------------------------------------------------------------------------- run Strand 1
python3 /app/extract_fields.py /app/permit_form.pdf > /app/form_fields.json

# ------------------------------------------------------------------------- run Strand 2
python3 - <<'PY'
from rdflib import Graph

QUERY = open("/app/query.rq").read()
g = Graph()
g.parse("/app/registry.ttl", format="turtle")
rows = sorted(
    (str(r["recruit"]), str(r["firm"]))
    for r in g.query(QUERY)
)
with open("/app/results.csv", "w", newline="") as fh:
    fh.write("recruit,firm\n")
    for recruit, firm in rows:
        fh.write("%s,%s\n" % (recruit, firm))
PY

# ------------------------------------------------------------------------- run Strand 3
python3 /app/decode_mesh.py /app/hull_rig.bin /app/mesh_arrays.npz

echo "solve done"
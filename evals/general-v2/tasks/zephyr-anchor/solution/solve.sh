#!/bin/bash
# Oracle for zephyr-anchor: writes the four deliverables under /app
# and produces every requested artifact by RUNNING that work.
set -euo pipefail


# ---- deliverable: /app/window.py ----
cat > /app/window.py <<'PYEOF'
#!/usr/bin/env python3
"""Generate a DNA string whose G+C composition stays inside a stated
percentage range in every contiguous sliding window of a fixed length.

Contract:
    python3 /app/window.py <out_path> <length> <window> <gc_min> <gc_max>

Writes exactly `length` nucleotides (only A, C, G, T) to <out_path> as a single
line followed by a trailing newline (no other whitespace). For EVERY contiguous
window of length <window> the percentage of G+C nucleotides must lie within
[gc_min, gc_max] inclusive. The provided inputs are guaranteed to admit a
feasible integer count k of G/C per window (i.e. ceil(gc_min%*W/100) <=
floor(gc_max%*W/100)). Exit status 0 on success.
"""

import sys


import math


def generate(length, window, gc_min, gc_max):
    """Return a DNA string of length `length` satisfying the window GC bound."""
    # Number of G/C nucleotides per window that make k/W*100 in [gc_min,gc_max].
    lo = max(0, int(math.ceil(gc_min * window / 100.0)))   # ceil(min%*W/100)
    hi = min(window, int(math.floor(gc_max * window / 100.0)))  # floor(max%*W/100)
    k = hi if hi >= lo else lo

    # Build one window-width period holding exactly k G/C, spread evenly,
    # with the remaining (window-k) positions alternating A/T.
    period = ["A"] * window
    if window > 0 and k > 0:
        step = window / k
        gcs = [int(i * step) for i in range(k)]
        for n, idx in enumerate(gcs):
            period[idx] = "G" if n % 2 == 0 else "C"
    # fill non-GC cells with a balanced A/T pattern
    at = ["A", "T"]
    j = 0
    for i in range(window):
        if period[i] == "A":
            period[i] = at[j % 2]
            j += 1

    # Tile the period up to `length`. Because the period length equals the
    # window length, every length-`window` contiguous substring is a rotation
    # of the period and contains exactly k G/C => always inside the range.
    out = []
    i = 0
    while len(out) < length:
        out.append(period[i % window])
        i += 1
    return "".join(out)


def main(argv):
    if len(argv) != 6:
        sys.stderr.write(
            "usage: window.py <out_path> <length> <window> <gc_min> <gc_max>\n")
        return 2
    out_path = argv[1]
    length = int(argv[2])
    window = int(argv[3])
    gc_min = float(argv[4])
    gc_max = float(argv[5])
    if window <= 0 or length <= 0:
        sys.stderr.write("length and window must be positive\n")
        return 2
    seq = generate(length, window, gc_min, gc_max)
    with open(out_path, "w") as fh:
        fh.write(seq + "\n")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/window.py

# ---- deliverable: /app/fasta.py ----
cat > /app/fasta.py <<'PYEOF'
#!/usr/bin/env python3
"""Write a well-formed FASTA PAIR file from a single template FASTA.

Contract:
    python3 /app/fasta.py <template.fa> <output.fa>

Reads a FASTA file containing exactly ONE record (header + one or more sequence
lines; header description text is ignored; blank lines are ignored during
parsing; sequence may be mixed-case). Writes <output.fa> containing EXACTLY two
records, in forward-first order:

    >NAME                       <- record 1 header (first token, no '>')
    <forward sequence uppercase, wrapped at 80 columns>
    >NAME_rc                    <- record 2 header
    <reverse complement, uppercase, wrapped at 80 columns>

NAME is the first whitespace-delimited token of the template header with the
leading '>' removed. The file contains NO blank lines anywhere, every line ends
without trailing spaces, and the file ends with a single trailing newline.
Sequence characters are restricted to A/C/G/T (all uppercase on output).
Exit status 0 on success.

Reverse complement: reverse the sequence (5'->3' becomes the reverse order),
then complement each base A<->T and G<->C, always emitting uppercase.
"""

import sys

_COMP = {"A": "T", "C": "G", "G": "C", "T": "A"}
_WIDTH = 80


def revcomp(seq):
    return "".join(_COMP[ch] for ch in "".join(
        ch.upper() for ch in seq)[::-1])


def parse_single_fasta(text):
    """Return (name, sequence) for a single-record FASTA or raise ValueError."""
    name = None
    seq = []
    header_seen = False
    body_started = False
    for line in text.split("\n"):
        if line.startswith(">"):
            if header_seen:
                raise ValueError("more than one record")
            header_seen = True
            tok = line[1:].split()
            name = tok[0] if tok else ""
        else:
            if line.strip():
                seq.append(line.strip())
    if not header_seen or name == "":
        raise ValueError("missing or empty header")
    return name, "".join(seq)


def wrap(seq, width=_WIDTH):
    return [seq[i:i + width] for i in range(0, len(seq), width)] or [""]


def build_pair(name, seq):
    out = [">" + name + "\n"]
    out += [line + "\n" for line in wrap(seq.upper())]
    out += [">" + name + "_rc\n"]
    out += [line + "\n" for line in wrap(revcomp(seq.upper()))]
    return "".join(out)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: fasta.py <template.fa> <output.fa>\n")
        return 2
    in_path, out_path = argv[1], argv[2]
    with open(in_path) as fh:
        text = fh.read()
    name, seq = parse_single_fasta(text)
    seq = seq.upper()
    if not set(seq) <= set("ACGT"):
        sys.stderr.write("template contains non-ACGT characters\n")
        return 2
    with open(out_path, "w") as fh:
        fh.write(build_pair(name, seq))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/fasta.py

# ---- deliverable: /app/smiles.py ----
cat > /app/smiles.py <<'PYEOF'
#!/usr/bin/env python3
"""Convert SMILES strings to RDKit Mol objects, returning None for invalid or
empty input instead of raising.

Contract:
    python3 /app/smiles.py <catalog.json> <report.json>

<catalog.json> maps an arbitrary sample id -> a SMILES string (may contain
empty/whitespace and malformed values). The script writes <report.json> as a
JSON object mapping each sample id to either:
    {"valid": true, "atoms": <N>}   for a non-empty, parse-able SMILES
    null                            for an invalid or empty/whitespace-only SMILES
It must NEVER raise or exit non-zero on any input; a malformed string yields
null in the report. The module also exposes a reusable convert() function.
"""

import json
import sys

from rdkit import Chem, RDLogger

RDLogger.DisableLog("rdApp.*")


def convert(smiles):
    """Return an RDKit Mol for a non-empty, valid SMILES, else None.

    Empty or whitespace-only input is treated as invalid (returns None), even
    though RDKit's MolFromSmiles would return an empty Mol object for "".
    """
    if not isinstance(smiles, str):
        return None
    if not smiles.strip():
        return None
    try:
        return Chem.MolFromSmiles(smiles)
    except Exception:
        return None


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: smiles.py <catalog.json> <report.json>\n")
        return 2
    in_path, out_path = argv[1], argv[2]
    with open(in_path) as fh:
        catalog = json.load(fh)
    report = {}
    if isinstance(catalog, dict):
        for sid, smi in catalog.items():
            mol = convert(smi)
            report[sid] = (None if mol is None
                           else {"valid": True, "atoms": mol.GetNumAtoms()})
    with open(out_path, "w") as fh:
        json.dump(report, fh, indent=2)
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/smiles.py

# ---- deliverable: /app/api_client.py ----
cat > /app/api_client.py <<'PYEOF'
#!/usr/bin/env python3
"""api_client: query the localhost spectra/structure API and join project
membership to employee records.

Contract:
    python3 /app/api_client.py <data_dir> <out.json>

<data_dir> must contain:
    api.json       list of {"id","sequence","excitation_nm","emission_nm"}
    employees.json list of {"id","name","department"}
    projects.json  list of {"id","department","member_ids":[...]}
    spec.json      {"donor":{"emission_min","emission_max"},
                    "acceptor":{"excitation_min","excitation_max"},
                    "sequence_ids":[...], "project_ids":[...]}

Steps:
1. Start the local fixture server  python3 /app/api_server.py <data_dir>/api.json
   <port>  on a free 127.0.0.1 port and poll /healthz until ready.
2. For every protein in the DB, query GET /api/spectra?id=<id>. Choose
   donor  = the unique protein whose emission_nm lies in
            [donor.emission_min, donor.emission_max];
   acceptor = the unique protein whose excitation_nm lies in
            [acceptor.excitation_min, acceptor.excitation_max].
   The seed data guarantees exactly one protein satisfies each side (the two
   windows are disjoint and each selects a distinct protein).
3. For each sid in spec.sequence_ids, query GET /api/sequences?id=<sid> and
   record the returned amino-acid sequence unchanged.
4. For each pid in spec.project_ids, look up projects.json and resolve EVERY
   member_id against employees.json, keeping only employees whose department
   equals the project's department. Seed data guarantees every member resolves.

Writes <out.json>:
    {
      "donor":    {"id","excitation_nm","emission_nm"},
      "acceptor": {"id","excitation_nm","emission_nm"},
      "sequences": { "<id>": "<amino-acid sequence>" },
      "projects": {
          "<project id>": {
              "resolved_members": [
                  {"member_id","employee_id","name","department"} ],
              "unresolved_member_ids": []
          }
      }
    }
Exit status 0 on success. Never reads the verifier fixtures.
"""

import json
import os
import socket
import subprocess
import sys
import time
import urllib.request

SERVER = "/app/api_server.py"
BASE = "http://127.0.0.1:%d"


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_server(api_path, port):
    proc = subprocess.Popen(
        [sys.executable, SERVER, api_path, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(120):
        try:
            with urllib.request.urlopen(
                    (BASE % port) + "/health", timeout=0.4) as r:
                if r.status == 200:
                    return proc
        except Exception:
            time.sleep(0.1)
    proc.terminate()
    raise RuntimeError("fixture server did not become ready")


def get_json(url):
    with urllib.request.urlopen(url, timeout=5) as r:
        return json.load(r)


def load(path):
    with open(path) as fh:
        return json.load(fh)


def run(data_dir, out_path):
    api_path = os.path.join(data_dir, "api.json")
    spec = load(os.path.join(data_dir, "spec.json"))
    employees = load(os.path.join(data_dir, "employees.json"))
    projects = load(os.path.join(data_dir, "projects.json"))
    db = load(api_path)

    port = free_port()
    proc = start_server(api_path, port)
    try:
        donor = None
        acceptor = None
        for rec in db:
            sp = get_json((BASE % port) + "/api/spectra?id=" + rec["id"])
            if spec["donor"]["emission_min"] <= sp["emission_nm"] <= \
                    spec["donor"]["emission_max"]:
                donor = sp
            if spec["acceptor"]["excitation_min"] <= sp["excitation_nm"] <= \
                    spec["acceptor"]["excitation_max"]:
                acceptor = sp

        sequences = {}
        for sid in spec["sequence_ids"]:
            sequences[sid] = get_json(
                (BASE % port) + "/api/sequences?id=" + sid)["sequence"]

        emp_by_id = {e["id"]: e for e in employees}
        proj_by_id = {p["id"]: p for p in projects}
        project_out = {}
        for pid in spec["project_ids"]:
            proj = proj_by_id[pid]
            resolved = []
            unresolved = []
            for member in proj["member_ids"]:
                emp = emp_by_id.get(member)
                if emp and emp["department"] == proj["department"]:
                    resolved.append({
                        "member_id": member,
                        "employee_id": emp["id"],
                        "name": emp["name"],
                        "department": emp["department"],
                    })
                else:
                    unresolved.append(member)
            project_out[pid] = {
                "resolved_members": resolved,
                "unresolved_member_ids": unresolved,
            }

        report = {
            "donor": donor,
            "acceptor": acceptor,
            "sequences": sequences,
            "projects": project_out,
        }
        with open(out_path, "w") as fh:
            json.dump(report, fh, indent=2)
        return 0
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=3)
        except Exception:
            proc.kill()


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: api_client.py <data_dir> <out.json>\n")
        return 2
    return run(argv[1], argv[2])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PYEOF
chmod +x /app/api_client.py

# Produce every artifact by RUNNING the deliverables.
python3 /app/window.py /app/window_out.txt 600 50 40 60
python3 /app/fasta.py /app/template.fa /app/pair.fa
python3 /app/smiles.py /app/catalog.json /app/smiles_report.json
python3 /app/api_client.py /app/data /app/api_report.json

echo "zephyr-anchor deliverables produced OK" >&2

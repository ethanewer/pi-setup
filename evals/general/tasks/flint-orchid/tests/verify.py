#!/usr/bin/env python3
"""flint-orchid verifier helper. Runs the agent's reusable /app tools on the
hidden inputs and independently recomputes every expected value from the raw
fixtures. Exits non-zero (reward 0) on any mismatch.
"""
import csv
import glob
import json
import os
import subprocess
import sys

import numpy as np
from bs4 import BeautifulSoup
from pypdf import PdfReader
from rdflib import Graph, Namespace

HID = "/tests/hidden"
failures = []


def fail(msg):
    failures.append(msg)
    print("VERIFY FAIL:", msg, file=sys.stderr)


# ---------------- PDF fields ----------------
def pdf_fields(path):
    reader = PdfReader(path)
    fields = reader.get_fields() or {}
    out = []
    for name, f in fields.items():
        out.append({"name": str(name), "label": str(f.get("/TU") or name)})
    out.sort(key=lambda e: e["name"])
    return out


# 1) visible deliverable equals independent parse of the visible form
exp_vis = pdf_fields("/app/data/registration_form.pdf")
try:
    with open("/app/form_fields.json") as fh:
        got_vis = json.load(fh)
    if got_vis != exp_vis:
        fail("form_fields.json != independent parse of visible form")
except Exception as e:
    fail("cannot read /app/form_fields.json: %r" % e)

# 2) hidden forms: run the agent's /app/parse_form.py and compare
for pdfpath in sorted(glob.glob(HID + "/pdf/*.pdf")):
    tmp = "/tmp/_vf_form.json"
    try:
        subprocess.run([sys.executable, "/app/parse_form.py", pdfpath, tmp],
                       check=True, capture_output=True)
        with open(tmp) as fh:
            got = json.load(fh)
    except Exception as e:
        fail("parse_form on %s failed: %r" % (os.path.basename(pdfpath), e))
        continue
    exp = pdf_fields(pdfpath)
    if got != exp:
        fail("parse_form mismatch on %s" % os.path.basename(pdfpath))


# ---------------- financial metrics ----------------
def fin_parse(path):
    soup = BeautifulSoup(open(path, encoding="utf-8").read(), "html.parser")
    table = soup.find("table", id="metrics")
    if table is None:
        return []
    # Every <tr> in the table counts toward the row index, including rows
    # nested inside <thead>/<tbody> (the header <tr> is row 1 per the
    # documented contract). Document order == index order.
    rows = table.find_all("tr")
    out = []
    for idx, tr in enumerate(rows, start=1):
        if "total" in (tr.get("class") or []):
            continue
        tds = tr.find_all("td", recursive=False)
        if len(tds) != 2:
            continue
        name = tds[0].get_text(" ", strip=True)
        t = tds[1].get_text(strip=True).replace(",", "").replace("$", "").strip()
        try:
            float(t)
        except ValueError:
            continue
        if not name:
            continue
        out.append({"metric": name, "amount": t, "row": idx})
    out.sort(key=lambda e: e["row"])
    return out


try:
    with open("/app/financials.json") as fh:
        if json.load(fh) != fin_parse("/app/data/financials.html"):
            fail("financials.json != independent parse of visible HTML")
except Exception as e:
    fail("cannot read /app/financials.json: %r" % e)

for htmlpath in sorted(glob.glob(HID + "/html/*.html")):
    tmp = "/tmp/_vf_fin.json"
    try:
        subprocess.run([sys.executable, "/app/parse_financials.py", htmlpath, tmp],
                       check=True, capture_output=True)
        with open(tmp) as fh:
            got = json.load(fh)
    except Exception as e:
        fail("parse_financials on %s failed: %r" % (os.path.basename(htmlpath), e))
        continue
    if got != fin_parse(htmlpath):
        fail("parse_financials mismatch on %s" % os.path.basename(htmlpath))


# ---------------- RDF relationships ----------------
def rdf_expected(ttl_path):
    # Independent walk: person ex:name + person ex:worksAt org; keep a row
    # only when both the person and the org carry an ex:name.
    g = Graph()
    g.parse(ttl_path, format="turtle")
    NS = Namespace("http://supplywire.example/")
    nmap = {}
    for s, o in g.subject_objects(NS["name"]):
        nmap[str(s)] = str(o)
    pairs = set()
    for p, o in g.subject_objects(NS["worksAt"]):
        if str(p) in nmap and str(o) in nmap:
            pairs.add((nmap[str(p)], nmap[str(o)]))
    return sorted(pairs)


def run_query(ttl_path):
    g = Graph()
    g.parse(ttl_path, format="turtle")
    q = open("/app/query.rq").read()
    rows = sorted({(str(r[0]), str(r[1])) for r in g.query(q)})
    return rows


# query must project the exact required result variables
qtext = open("/app/query.rq").read()
if "?person" not in qtext or "?org" not in qtext:
    fail("query.rq does not project ?person and ?org")

# visible results.csv vs independent walk of visible data
exp_vis = rdf_expected("/app/data/relations.ttl")
try:
    with open("/app/results.csv", newline="") as fh:
        rd = list(csv.reader(fh))
    if rd[0] != ["person", "org"]:
        fail("results.csv header != person,org")
    got_vis = sorted([(r[0], r[1]) for r in rd[1:]])
    if got_vis != exp_vis:
        fail("results.csv row set != independent walk of visible TTL")
except Exception as e:
    fail("cannot read /app/results.csv: %r" % e)

# hidden TTLs: agent's query.rq run vs independent walk
for ttl in sorted(glob.glob(HID + "/rdf/*.ttl")):
    try:
        got = run_query(ttl)
        exp = rdf_expected(ttl)
    except Exception as e:
        fail("query.rq run on %s errored: %r" % (os.path.basename(ttl), e))
        continue
    if got != exp:
        fail("query.rq mismatch on %s" % os.path.basename(ttl))


# ---------------- mesh decode ----------------
def mesh_independent(path):
    raw = open(path, "rb").read()
    V = int(np.frombuffer(raw[8:12], dtype="<u4")[0])
    B = int(np.frombuffer(raw[12:16], dtype="<u4")[0])
    v = np.frombuffer(raw[16:16 + V * 44], dtype=np.uint8).reshape(V, 44)
    positions = v[:, 0:12].copy().view("<f4").reshape(V, 3)
    normals = v[:, 12:24].copy().view("<f4").reshape(V, 3)
    texcoords = v[:, 24:32].copy().view("<f4").reshape(V, 2)
    weights = v[:, 32:36].copy()
    bones = v[:, 36:44].copy().view("<u2").reshape(V, 4)
    sk = np.frombuffer(raw[16 + V * 44:16 + V * 44 + B * 30], dtype=np.uint8).reshape(B, 30)
    parents = sk[:, 0:2].copy().view("<i2").reshape(B)
    bind_pose = np.concatenate([sk[:, 2:14].copy().view("<f4").reshape(B, 3),
                                sk[:, 14:30].copy().view("<f4").reshape(B, 4)], axis=1)
    return {"positions": positions, "normals": normals, "texcoords": texcoords,
            "weights": weights, "bones": bones, "parents": parents, "bind_pose": bind_pose}


KEYS = ["positions", "normals", "texcoords", "weights", "bones", "parents", "bind_pose"]


def arrays_equal(a, b):
    return a.shape == b.shape and a.dtype == b.dtype and np.array_equal(a, b)


def check_npz(npz_path, indep):
    z = np.load(npz_path)
    if set(z.files) != set(KEYS):
        fail("npz keys %s != %s" % (sorted(z.files), KEYS))
        return
    for k in KEYS:
        if not arrays_equal(z[k], indep[k]):
            fail("mesh array %r mismatch (shape %s/%s dtype %s/%s)" %
                 (k, z[k].shape, indep[k].shape, z[k].dtype, indep[k].dtype))


# visible mesh deliverable
try:
    check_npz("/app/mesh_arrays.npz", mesh_independent("/app/data/rigged_pump.bin"))
except Exception as e:
    fail("cannot validate /app/mesh_arrays.npz: %r" % e)

# hidden valid meshes
for name in ["h1_ok.bin", "h2_zero.bin", "h3_big.bin"]:
    src = HID + "/mesh/" + name
    out = "/tmp/_vf_mesh.npz"
    try:
        r = subprocess.run([sys.executable, "/app/decode_mesh.py", src, out],
                           capture_output=True)
        if r.returncode != 0:
            fail("decode_mesh non-zero on %s" % name)
            continue
        check_npz(out, mesh_independent(src))
    except Exception as e:
        fail("decode_mesh %s errored: %r" % (name, e))

# hidden malformed meshes must fail cleanly (non-zero, no output)
for name in ["bad_trunc.bin", "bad_ver.bin", "bad_magic.bin"]:
    src = HID + "/mesh/" + name
    out = "/tmp/_vf_bad.npz"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, "/app/decode_mesh.py", src, out],
                           capture_output=True)
        if r.returncode == 0:
            fail("decode_mesh should have failed on malformed %s" % name)
        if os.path.exists(out):
            fail("decode_mesh wrote output for malformed %s" % name)
    except Exception as e:
        fail("decode_mesh %s errored unexpectedly: %r" % (name, e))

if failures:
    for f in failures:
        print("VERIFIER FAIL:", f, file=sys.stderr)
    sys.exit(1)
print("verify.py: all checks passed")
sys.exit(0)

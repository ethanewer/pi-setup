#!/usr/bin/env python3
"""Generate all visible + hidden fixtures for flint-orchid. Author-only tool.
Run with the host venv that has reportlab/pypdf/bs4/rdflib/numpy.
"""
import os, struct, random
from reportlab.pdfgen.canvas import Canvas
from reportlab.lib.pagesizes import letter
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIS = os.path.join(ROOT, "environment", "files", "data")
HID = os.path.join(ROOT, "tests", "hidden")

def pdf(path, fields):
    c = Canvas(path, pagesize=letter)
    c.setFont('Helvetica', 11)
    x, y = 72, 720
    for (name, kind, label, tooltip, opts) in fields:
        c.drawString(x, y, label)
        tt = tooltip if tooltip is not None else label
        if kind == 'text':
            c.acroForm.textfield(name=name, tooltip=tt, x=x+200, y=y-5, width=180, height=20)
        elif kind == 'checkbox':
            c.acroForm.checkbox(name=name, tooltip=tt, x=x+200, y=y-5, size=15)
        elif kind == 'radio':
            for v in opts:
                c.acroForm.radio(name=name, value=v, tooltip=tt, x=x+200, y=y-5, size=15)
        y -= 34
    c.showPage(); c.save()

def mesh(path, V, B, seedbase):
    with open(path, 'wb') as f:
        f.write(b'KMSH'); f.write(struct.pack('<I', 3))
        f.write(struct.pack('<I', V)); f.write(struct.pack('<I', B))
        for i in range(V):
            r = random.Random(seedbase + i)
            pos = (round(r.uniform(-5, 5), 5), round(r.uniform(-5, 5), 5), round(r.uniform(-5, 5), 5))
            uv = (round(r.uniform(0, 1), 5), round(r.uniform(0, 1), 5))
            ws = [255, 0, 0, 0]; bs = [i % max(B, 1), 0, 0, 0]
            f.write(struct.pack('<3f', *pos)); f.write(struct.pack('<3f', 0.0, 0.0, 1.0))
            f.write(struct.pack('<2f', *uv)); f.write(bytes(ws)); f.write(struct.pack('<4H', *bs))
        for j in range(B):
            r = random.Random(seedbase + 500 + j)
            parent = j - 1 if j > 0 else -1
            pos = (round(r.uniform(-1, 1), 4), round(r.uniform(-1, 1), 4), round(r.uniform(-1, 1), 4))
            f.write(struct.pack('<h', parent)); f.write(struct.pack('<3f', *pos)); f.write(struct.pack('<4f', 1.0, 0.0, 0.0, 0.0))

def ttl_from(pairs_extra):
    """pairs: list of (person_name, org_name, org_has_name). node ids auto.
    Also allow an extra person with NO worksAt triple (must be excluded)."""
    out = ["@prefix ex: <http://supplywire.example/> .", ""]
    lines = []
    pn = 0; on = 0
    for (pname, oname, org_has_name) in pairs_extra:
        pid = "p%d" % pn; pn += 1
        lines.append("ex:%s ex:name \"%s\" ;" % (pid, pname))
        oid = "o%d" % on; on += 1
        lines.append("    ex:worksAt ex:%s ." % oid)
        lines.append("")
        if org_has_name:
            lines.append("ex:%s a ex:Org ; ex:name \"%s\" ." % (oid, oname))
        else:
            lines.append("ex:%s a ex:Org ." % oid)
        lines.append("")
    # person with no relationship
    lines.append("ex:p%d a ex:People ; ex:name \"Orphan solo\" ." % pn)
    lines.append("")
    return "\n".join(out) + "\n".join(lines)

os.makedirs(VIS, exist_ok=True); os.makedirs(HID, exist_ok=True)

# ---------------- VISIBLE ----------------
pdf(os.path.join(VIS, "registration_form.pdf"), [
    ('f_serial', 'text', 'Serial number', None, None),
    ('f_name', 'text', 'Operator name', None, None),
    ('f_active', 'checkbox', 'Currently active', None, None),
    ('f_shift', 'radio', 'Work shift', None, ['D', 'N']),
    ('f_area', 'text', 'Site area code', None, None),
    ('f_notes', 'text', 'Field notes', 'Field notes free text', None),
])

open(os.path.join(VIS, "financials.html"), 'w').write("""<!doctype html>
<html><head><title>Quarterly Lodgings</title></head><body>
<h1>Q3 Lodgings Summary</h1>
<table id="metrics">
<thead><tr><th>Line item</th><th>Amount</th></tr></thead>
<tbody>
<tr><td>Revenue</td><td>1,600,000</td></tr>
<tr><td>Cost of goods</td><td>620,000</td></tr>
<tr class="total"><td>Gross profit</td><td>980,000</td></tr>
<tr><td>—</td></tr>
<tr><td>Research spend</td><td>n/a</td></tr>
<tr><td>Marketing budget</td><td>$255,000</td></tr>
<tr><td>Inventory</td><td>412,000</td></tr>
<tr><td>Payroll</td><td>740,000</td></tr>
</tbody></table>
</body></html>
""")

open(os.path.join(VIS, "relations.ttl"), 'w').write(ttl_from([
    ("Alice", "Acme Foundry", True),
    ("Bob", "Acme Foundry", True),
    ("Bob", "Beacon Labs", True),
    ("Carol", "Beacon Labs", True),
    ("Dave", "Duskworks", False),   # org has no name -> excluded from results
]))

# skinned mesh: 24 vertices, 9 bones
mesh(os.path.join(VIS, "rigged_pump.bin"), 24, 9, 1000)

# ---------------- HIDDEN ----------------
os.makedirs(os.path.join(HID, "pdf"), exist_ok=True)
os.makedirs(os.path.join(HID, "html"), exist_ok=True)
os.makedirs(os.path.join(HID, "rdf"), exist_ok=True)
os.makedirs(os.path.join(HID, "mesh"), exist_ok=True)

# h_pdf1: unlike set of fields, one field lacks a tooltip (label falls back to name)
pdf(os.path.join(HID, "pdf", "h1_nolabel.pdf"), [
    ('stamp', 'text', 'Depot stamp', None, None),
    ('s_id', 'text', 'Sensor identifier', 'Identifier of the sensor', None),
    ('cal', 'checkbox', 'Calibrated', 'Calibration performed', None),
    ('band', 'radio', 'Band', None, ['A', 'B', 'C']),
])
pdf(os.path.join(HID, "pdf", "h2_basic.pdf"), [
    ('part', 'text', 'Part number', 'Part number', None),
    ('qty', 'text', 'Quantity', 'Quantity on hand', None),
    ('checked', 'checkbox', 'Inspected', 'Final inspection done', None),
])
# h_pdf3: a very small form with a single checkbox only
pdf(os.path.join(HID, "pdf", "h3_few.pdf"), [
    ('ok', 'checkbox', 'Is complete', None, None),
])

# ---------------- hidden html ----------------
def html_case(name, table):
    open(os.path.join(HID, "html", name), 'w').write(
        "<html><body><h2>Ledger</h2>\n<table id=\"metrics\">\n%s\n</table></body></html>" % table)

html_case("h1.html", "\n".join([
    "<thead><tr><th>Metric</th><th>Figure</th></tr></thead>",
    "<tr><td>Units sold</td><td>48,000</td></tr>",
    "<tr><td>Returns</td><td>1,200</td></tr>",
    "<tr class=\"total\"><td>Net units</td><td>46,800</td></tr>",
    "<tr><td class=\"note\">Year to date</td></tr>",
    "<tr><td>Warranty claims</td><td>—</td></tr>",
    "<tr><td>Service revenue</td><td>$99,500</td></tr>",
    "<tr><td>  Devices repaired  </td><td>  3,400  </td></tr>",
]))
html_case("h2.html", "\n".join([
    "<tr><th>Metric</th><th>Value</th></tr>",
    "<tr><td>Telemetry events</td><td>2,300,000</td></tr>",
    "<tr><td> </td><td> 550,000 </td></tr>",   # empty label -> not a metric, still counted
    "<tr class=\"total\"><td>Alerts</td><td>88,000</td></tr>",
    "<tr><td>Open work orders</td><td>1,175</td></tr>",
    "<tr><td>Backlog age</td><td>days</td></tr>",  # non numeric
    "<tr><td>Crew hours</td><td>12,500</td></tr>",
]))
html_case("h3.html", "\n".join([
    "<tr><th>Metric</th><th>Amount</th></tr>",
    "<tr><td>Licenses</td><td>7,700</td></tr>",
    "<tr><td>Renewals due</td><td>310</td></tr>",
]))

# ---------------- hidden rdf ----------------
open(os.path.join(HID, "rdf", "h1.ttl"), 'w').write(ttl_from([
    ("Malik", "Horizon Forge", True),
    ("Priya", "Horizon Forge", True),
    ("Priya", "Northwind Spools", True),
    ("Juno", "Northwind Spools", True),
    ("Rook", "Vaultline", False),  # no name -> excluded
    ("Sven", "Lumenworks", True),
]))
open(os.path.join(HID, "rdf", "h2.ttl"), 'w').write(ttl_from([
    ("Nadia", "Bluepeak", True),
    ("Otto", "Bluepeak", True),
    ("Quinn", "Emberline", True),
]))
# h3_edge: duplicate (same person-org) statement repeated -> must dedupe
open(os.path.join(HID, "rdf", "h3_dup.ttl"), 'w').write("""
@prefix ex: <http://supplywire.example/> .
ex:p0 ex:name "Dup" ; ex:worksAt ex:o0 .
ex:p0 ex:worksAt ex:o0 .
ex:o0 a ex:Org ; ex:name "Twinfold" .
ex:p1 ex:name "Ghost" ; ex:worksAt ex:o1 .
ex:o1 a ex:Org ; ex:name "Halfmoon" .
""")
# h4_empty: empty dataset -> empty result set
open(os.path.join(HID, "rdf", "h4_empty.ttl"), 'w').write(
    "@prefix ex: <http://supplywire.example/> .\nex:z ex:name \"Nothing\" .\n")

# ---------------- hidden mesh ----------------
mesh(os.path.join(HID, "mesh", "h1_ok.bin"), 48, 13, 3000)
mesh(os.path.join(HID, "mesh", "h2_zero.bin"), 0, 4, 4000)   # zero-vertex mesh (valid)
mesh(os.path.join(HID, "mesh", "h3_big.bin"), 501, 31, 5000)
# malformed: truncated (drop tail bytes)
raw = bytearray(open(os.path.join(HID, "mesh", "h1_ok.bin"), 'rb').read())
open(os.path.join(HID, "mesh", "bad_trunc.bin"), 'wb').write(raw[:-23])
# malformed: wrong version
b = bytearray(open(os.path.join(HID, "mesh", "h1_ok.bin"), 'rb').read())
struct.pack_into('<I', b, 4, 7)
open(os.path.join(HID, "mesh", "bad_ver.bin"), 'wb').write(b)
# malformed: bad magic
b = bytearray(open(os.path.join(HID, "mesh", "h1_ok.bin"), 'rb').read())
b[0:4] = b'ZZZZ'
open(os.path.join(HID, "mesh", "bad_magic.bin"), 'wb').write(b)

print("generated:", VIS, HID)

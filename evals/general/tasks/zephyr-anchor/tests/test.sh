#!/bin/bash
# Verifier for zephyr-anchor: exercises all four deliverables on the visible
# fixtures and on the hidden cases, checking every competency gate, then writes
# a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
python3 - <<'PYEOF' >&2
import json, glob, os, shutil, subprocess, sys

failures = []

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def load(p):
    with open(p) as fh:
        return json.load(fh)

def revcomp(seq):
    comp = {"A":"T","C":"G","G":"C","T":"A"}
    return "".join(comp[c] for c in "".join(ch.upper() for ch in seq)[::-1])

def ref_smiles(s):
    """Independent reference: None unless s is a non-blank parseable SMILES."""
    if not isinstance(s, str) or not s.strip():
        return None
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    m = Chem.MolFromSmiles(s)
    return None if m is None else {"valid": True, "atoms": m.GetNumAtoms()}

# --------------------------------------------------------------- helpers

def check_window(path, length, window, gc_min, gc_max):
    try:
        text = open(path).read()
    except IOError:
        return False
    s = text.rstrip("\n")
    if "\n" in s or len(s) != length or not set(s) <= set("ACGT"):
        return False
    if window > length:
        return True
    for i in range(length - window + 1):
        w = s[i:i + window]
        frac = 100.0 * (w.count("G") + w.count("C")) / window
        if frac < gc_min - 1e-9 or frac > gc_max + 1e-9:
            return False
    return True

def validate_window(args_list):
    for (out, length, window, gc_min, gc_max, label) in args_list:
        r = run(["python3", "/app/window.py", out,
                 str(length), str(window), str(gc_min), str(gc_max)])
        if r.returncode != 0:
            return "window(%s) non-zero exit" % label
        if not check_window(out, length, window, gc_min, gc_max):
            return "window(%s) constraint/length broken" % label
    return None

def parse_fasta(text):
    recs = []
    name = None; buf = []
    for line in text.split("\n"):
        if line.startswith(">"):
            if name is not None:
                recs.append((name, "".join(buf)))
            tok = line[1:].split()
            name = tok[0] if tok else ""
            buf = []
        elif line.strip():
            buf.append(line.strip().upper())
    if name is not None:
        recs.append((name, "".join(buf)))
    return recs

def check_fasta(out_path, template_path, label):
    if not os.path.exists(out_path):
        return "fasta(%s): missing output" % label
    text = open(out_path).read()
    for ln in text.rstrip("\n").split("\n"):
        if ln.strip() == "" or ln != ln.rstrip():
            return "fasta(%s): blank/stray-whitespace line" % label
    tname, tseq = parse_fasta(open(template_path).read())[0]
    recs = parse_fasta(text)
    if len(recs) != 2:
        return "fasta(%s): exactly 2 records required, got %d" % (label, len(recs))
    n1, s1 = recs[0]; n2, s2 = recs[1]
    if n1 != tname:
        return "fasta(%s): rec1 header %r want %r" % (label, n1, tname)
    if n2 != tname + "_rc":
        return "fasta(%s): rec2 header %r want %r" % (label, n2, tname + "_rc")
    if set(s1) - set("ACGT") or set(s2) - set("ACGT"):
        return "fasta(%s): non-ACGT symbol" % label
    if s1 != tseq.upper():
        return "fasta(%s): forward seq mismatch" % label
    if s2 != revcomp(tseq):
        return "fasta(%s): reverse-complement mismatch" % label
    return None

def check_smiles(path, catalog_path, label):
    if not os.path.exists(path):
        return "smiles(%s): missing report" % label
    cat = load(catalog_path); rep = load(path)
    if set(rep.keys()) != set(cat.keys()):
        return "smiles(%s): key set mismatch" % label
    for sid, smi in cat.items():
        if rep.get(sid) != ref_smiles(smi):
            return "smiles(%s): entry %r mismatch" % (label, sid)
    return None

def check_api(report_path, data_dir, label):
    if not os.path.exists(report_path):
        return "api(%s): missing report" % label
    rep = load(report_path)
    db = load(os.path.join(data_dir, "api.json"))
    by_id = {r["id"]: r for r in db}
    spec = load(os.path.join(data_dir, "spec.json"))
    donors = [r for r in db if
              spec["donor"]["emission_min"] <= r["emission_nm"] <=
              spec["donor"]["emission_max"]]
    accs   = [r for r in db if
              spec["acceptor"]["excitation_min"] <= r["excitation_nm"] <=
              spec["acceptor"]["excitation_max"]]
    if len(donors) != 1:
        return "api(%s): donor window not unique (%d)" % (label, len(donors))
    if len(accs) != 1:
        return "api(%s): acceptor window not unique (%d)" % (label, len(accs))
    want_d = {"id": donors[0]["id"],
              "excitation_nm": donors[0]["excitation_nm"],
              "emission_nm": donors[0]["emission_nm"]}
    want_a = {"id": accs[0]["id"],
              "excitation_nm": accs[0]["excitation_nm"],
              "emission_nm": accs[0]["emission_nm"]}
    if rep.get("donor") != want_d:
        return "api(%s): donor mismatch" % label
    if rep.get("acceptor") != want_a:
        return "api(%s): acceptor mismatch" % label
    seqs = rep.get("sequences") or {}
    for sid in spec["sequence_ids"]:
        if seqs.get(sid) != by_id[sid]["sequence"]:
            return "api(%s): sequence %s mismatch" % (label, sid)
    projs_m = {p["id"]: p for p in load(os.path.join(data_dir, "projects.json"))}
    emps_m  = {e["id"]: e for e in load(os.path.join(data_dir, "employees.json"))}
    got = rep.get("projects") or {}
    for pid in spec["project_ids"]:
        proj = projs_m.get(pid)
        if proj is None:
            return "api(%s): project %s missing in data" % (label, pid)
        expect_res = []
        for member in proj["member_ids"]:
            emp = emps_m.get(member)
            if emp and emp["department"] == proj["department"]:
                expect_res.append({"member_id": member,
                                   "employee_id": emp["id"],
                                   "name": emp["name"],
                                   "department": emp["department"]})
        g = got.get(pid)
        if g is None:
            return "api(%s): project %s missing in report" % (label, pid)
        if g.get("unresolved_member_ids") not in ([], None):
            return "api(%s): project %s has unresolved members" % (label, pid)
        if g.get("resolved_members") != expect_res:
            return "api(%s): project %s join mismatch" % (label, pid)
    return None

# ------------------------------------------------------------- presence
found_any = False
for d in ["window.py", "fasta.py", "smiles.py", "api_client.py"]:
    if os.path.exists("/app/" + d):
        found_any = True
    else:
        failures.append("missing deliverable /app/" + d)
for f in ["window_out.txt", "pair.fa", "smiles_report.json", "api_report.json"]:
    if not os.path.exists("/app/" + f):
        failures.append("missing artifact /app/" + f)

# ------------------------------------------------------------- visible runs
work = "/tmp/zeph_verify"
os.makedirs(work, exist_ok=True)

if os.path.exists("/app/window.py"):
    vw = validate_window([
        (work + "/wv.txt", 600, 50, 40.0, 60.0, "visible")])
    if vw:
        failures.append(vw)
if os.path.exists("/app/window_out.txt"):
    if not check_window("/app/window_out.txt", 600, 50, 40.0, 60.0):
        failures.append("window_out.txt broken (600/50/40/60)")

# hidden window cases
for jp in sorted(glob.glob("/tests/hidden/window_*.json")):
    p = load(jp)
    out = os.path.join(work, "wh_" + os.path.basename(jp) + ".txt")
    v = None
    if os.path.exists("/app/window.py"):
        r = run(["python3", "/app/window.py", out,
                 str(p["length"]), str(p["window"]),
                 str(p["gc_min"]), str(p["gc_max"])])
        if r.returncode != 0:
            v = "window(%s) non-zero exit" % jp
        elif not check_window(out, p["length"], p["window"],
                              float(p["gc_min"]), float(p["gc_max"])):
            v = "window(%s) broken" % jp
    else:
        v = "window deliverable missing"
    if v:
        failures.append(v)

# ------------------------------------------------------------- fasta
if os.path.exists("/app/fasta.py"):
    # visible: produce pair and compare to artifact + reasoning
    r = run(["python3", "/app/fasta.py", "/app/template.fa",
             os.path.join(work, "pair_vis.fa")])
    if r.returncode != 0:
        failures.append("fasta visible non-zero exit")
    else:
        e = check_fasta(os.path.join(work, "pair_vis.fa"), "/app/template.fa",
                        "visible")
        if e:
            failures.append(e)
for inp in sorted(glob.glob("/tests/hidden/fasta_*.fa")):
    out = os.path.join(work, "fh_" + os.path.basename(inp) + ".fa")
    if not os.path.exists("/app/fasta.py"):
        failures.append("fasta deliverable missing")
        break
    r = run(["python3", "/app/fasta.py", inp, out])
    if r.returncode != 0:
        failures.append("fasta(%s) non-zero exit" % inp)
    else:
        e = check_fasta(out, inp, os.path.basename(inp))
        if e:
            failures.append(e)

# pair.fa artifact must itself be correct
if os.path.exists("/app/pair.fa"):
    e = check_fasta("/app/pair.fa", "/app/template.fa", "pair-artifact")
    if e:
        failures.append(e)
else:
    failures.append("missing artifact /app/pair.fa")

# ------------------------------------------------------------- smiles
if os.path.exists("/app/smiles.py"):
    r = run(["python3", "/app/smiles.py", "/app/catalog.json",
             os.path.join(work, "sm_vis.json")])
    if r.returncode != 0:
        failures.append("smiles visible non-zero exit")
    else:
        e = check_smiles(os.path.join(work, "sm_vis.json"), "/app/catalog.json",
                         "visible")
        if e:
            failures.append(e)
else:
    failures.append("smiles deliverable missing")
for jp in sorted(glob.glob("/tests/hidden/smiles_*.json")):
    out = os.path.join(work, "sm_" + os.path.basename(jp))
    r = run(["python3", "/app/smiles.py", jp, out])
    if r.returncode != 0:
        failures.append("smiles(%s) non-zero exit" % jp)
    else:
        e = check_smiles(out, jp, os.path.basename(jp))
        if e:
            failures.append(e)
if os.path.exists("/app/smiles_report.json"):
    e = check_smiles("/app/smiles_report.json", "/app/catalog.json",
                     "report-artifact")
    if e:
        failures.append(e)

# ------------------------------------------------------------- api client
# visible artifact and re-run
if os.path.exists("/app/api_client.py"):
    r = run(["python3", "/app/api_client.py", "/app/data",
             os.path.join(work, "api_vis.json")])
    if r.returncode != 0:
        failures.append("api visible non-zero exit")
    else:
        e = check_api(os.path.join(work, "api_vis.json"), "/app/data", "visible")
        if e:
            failures.append(e)
    for d in sorted(glob.glob("/tests/hidden/api_*")):
        if not os.path.isdir(d):
            continue
        cdir = os.path.join(work, "adat")
        if os.path.exists(cdir):
            shutil.rmtree(cdir)
        shutil.copytree(d, cdir)
        out = os.path.join(work, "api_hidden.json")
        rr = run(["python3", "/app/api_client.py", cdir, out])
        if rr.returncode != 0:
            failures.append("api(%s) non-zero exit" % d)
        else:
            e = check_api(out, cdir, os.path.basename(d))
            if e:
                failures.append(e)
else:
    failures.append("api deliverable missing")
if os.path.exists("/app/api_report.json"):
    e = check_api("/app/api_report.json", "/app/data", "report-artifact")
    if e:
        failures.append(e)

# ------------------------------------------------------------- verdict
if failures:
    for f in failures:
        print("VERIFY FAIL:", f, file=sys.stderr)
    reward = "0"
else:
    reward = "1"
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write(reward + "\n")
print("zephyr-anchor reward=" + reward)
PYEOF
echo "stub"
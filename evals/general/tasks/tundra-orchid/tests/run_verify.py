#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys

PAT = re.compile(
    r"^\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})\]"
    r"\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d{3})\s+(\d+)$"
)
HIDDEN = "/tests/hidden"
PASS = [True]


def parse_requests(path):
    out = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = PAT.match(line.strip())
            if m:
                ts, ip, method, ptok, status, size = m.groups()
                out.append((ts, ip, method, ptok, int(status), int(size)))
    return out


def gold_log(path):
    reqs = parse_requests(path)
    total = len(reqs)
    unique = len(set(r[1] for r in reqs))
    accepted = sum(1 for r in reqs if 200 <= r[4] <= 299)
    rate = f"{accepted/total:.3f}" if total else "0.000"
    ts500 = [r[0] for r in reqs if r[4] == 500]
    earliest = min(ts500) if ts500 else "NONE"
    return total, unique, accepted, rate, earliest


def run(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return out.returncode, out.stdout
    except Exception as e:
        return 1, "ERR " + repr(e)


def json_eq(text, expect):
    try:
        got = json.loads(text)
    except Exception:
        return False
    return isinstance(got, dict) and got == expect


def ok(cond, msg):
    if not cond:
        PASS[0] = False
        print("FAIL:", msg, file=sys.stderr)


# ---------- 0. existence gate ----------
REQUIRED = [
    "/app/analyze_logs.py", "/app/log_report.txt",
    "/app/answer.py", "/app/answer.txt",
    "/app/metric.py", "/app/metric.json",
    "/app/fixed_script.py", "/app/fixed_output.csv",
    "/app/merge_records.py", "/app/conflict_report.json",
]
for p in REQUIRED:
    if not os.path.isfile(p):
        print("missing deliverable", p, file=sys.stderr)
        sys.exit(1)

# ---------- 1. sample log: scripts output and delivered files ----------
SAMPLE = "/app/sample_access.log"
GT, GU, GA, GR, GE = gold_log(SAMPLE)
EXP_STATS = f"total_requests={GT}\nunique_clients={GU}\n"
GOLD_METRIC = {"accepted": GA, "total": GT, "acceptance_rate": GR}

rc, so = run(["python3", "/app/analyze_logs.py", SAMPLE])
ok(rc == 0 and so == EXP_STATS, f"analyze_logs sample output {so!r} want {EXP_STATS!r}")

rc, so = run(["python3", "/app/answer.py", SAMPLE])
ok(rc == 0 and so.strip() == GE, f"answer sample {so!r} want {GE!r}")

rc, so = run(["python3", "/app/metric.py", SAMPLE])
ok(rc == 0 and json_eq(so, GOLD_METRIC), f"metric sample {so!r} want {GOLD_METRIC!r}")

with open("/app/log_report.txt") as fh:
    ok(fh.read() == EXP_STATS, "log_report.txt content wrong")
with open("/app/answer.txt") as fh:
    ok(fh.read().strip() == GE, "answer.txt wrong")
with open("/app/metric.json") as fh:
    ok(json_eq(fh.read(), GOLD_METRIC), "metric.json wrong")

# ---------- 2. hidden logs generalize ----------
for name in ("log_a.txt", "log_b.txt"):
    h = os.path.join(HIDDEN, name)
    t, u, a, r, e = gold_log(h)
    rc, so = run(["python3", "/app/analyze_logs.py", h])
    ok(rc == 0 and so == f"total_requests={t}\nunique_clients={u}\n",
       f"hidden analyze {name}: {so!r}")
    rc, so = run(["python3", "/app/answer.py", h])
    ok(rc == 0 and so.strip() == e, f"hidden answer {name}: {so!r} want {e!r}")
    rc, so = run(["python3", "/app/metric.py", h])
    ok(rc == 0 and json_eq(so, {"accepted": a, "total": t, "acceptance_rate": r}),
       f"hidden metric {name}: {so!r}")

# ---------- 3. CSV pipeline ----------
def check_processed(infile, context, expect_list):
    outp = "/tmp/agent_out.csv"
    if os.path.exists(outp):
        os.remove(outp)
    rc, _ = run(["python3", "/app/fixed_script.py", infile, outp])
    if rc != 0 or not os.path.isfile(outp):
        ok(False, f"fixed_script failed on {context}")
        return
    with open(outp) as fh:
        physical = [ln for ln in fh.read().split("\n") if ln != ""]
    exp_lines = [f"{nm},{qt}" for nm, qt in expect_list]
    ok(physical == exp_lines, f"CSV {context} {physical!r} want {exp_lines!r}")
    for ln in physical:
        ok(re.fullmatch(r"[^,]+,\d+", ln) is not None and "\r" not in ln,
           f"CSV {context} polluted line {ln!r}")

SAMPLE_REC = "/app/sample_records.csv"
sample_expected = [("turbo fan", "12"), ("hub bolt", "7"), ("gear wheel", "5"),
                   ("split pin", "3"), ("socket washer", "2")]
check_processed(SAMPLE_REC, "sample", sample_expected)

tmp = "/tmp/sample_rerun.csv"
run(["python3", "/app/fixed_script.py", SAMPLE_REC, tmp])
ok(open(tmp).read() == open("/app/fixed_output.csv").read(),
   "fixed_script rerun != delivered fixed_output.csv")

h_expected = [("delta", "14"), ("gamma", "3"), ("delta", "3"), ("beta", "7"),
              ("omega", "5")]
check_processed(os.path.join(HIDDEN, "records_a.csv"), "hidden records", h_expected)

# ---------- 4. conflict report ----------
def check_conflict(infile, context, expected_conflicts):
    rc, so = run(["python3", "/app/merge_records.py", infile])
    if rc != 0:
        ok(False, f"merge_records failed on {context}")
        return
    expect = {"total_conflicts": len(expected_conflicts), "conflicts": expected_conflicts}
    ok(json_eq(so, expect), f"conflict {context}: {so!r} want {expect!r}")

sample_conf = [
    {"user": "alice", "field": "email",
     "sources": [{"source": "primary", "value": "alice@nimbus.dev"},
                 {"source": "backup", "value": "alice.alt@nimbus.dev"}],
     "winner": "alice@nimbus.dev"},
    {"user": "erin", "field": "tier",
     "sources": [{"source": "primary", "value": "enterprise"},
                 {"source": "backup", "value": "team"}],
     "winner": "enterprise"},
]
with open("/app/conflict_report.json") as fh:
    ok(json_eq(fh.read(), {"total_conflicts": 2, "conflicts": sample_conf}),
       "conflict_report.json wrong")
check_conflict("/app/people_records.csv", "sample", sample_conf)

hidden_conf = [
    {"user": "alice", "field": "email",
     "sources": [{"source": "primary", "value": "alice@northside.dev"},
                 {"source": "backup", "value": "alice.alt@northside.dev"}],
     "winner": "alice@northside.dev"},
    {"user": "wren", "field": "warehouse",
     "sources": [{"source": "primary", "value": "north"},
                 {"source": "backup", "value": "south"}],
     "winner": "north"},
    {"user": "flo", "field": "sla",
     "sources": [{"source": "primary", "value": "premium"},
                 {"source": "backup", "value": "lam"}],
     "winner": "premium"},
]
check_conflict(os.path.join(HIDDEN, "conflict_a.csv"), "hidden conflict", hidden_conf)

print(1 if PASS[0] else 0)
sys.exit(0)
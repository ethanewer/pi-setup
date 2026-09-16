#!/bin/bash
# Verifier for wale-haven (executes-deliverable).
#
# Executes /app/aggregate.py on the visible dataset and on every hidden
# fixture under /tests/hidden, and asserts:
#   * deliverable files exist; aggregate.py is stdlib-only, argv-driven and
#     does not special-case the shipped paths;
#   * shipped /app/periods.json and /app/events.csv are byte-identical
#     to the originals (checked against embedded pristine sha256 digests);
#   * /app/result.json agrees with a fresh run of the program on the visible
#     dataset;
#   * every total is exact, every period id is present, no extra keys;
#   * whichever boundary convention the program implements, it is applied
#     consistently across the visible and all hidden datasets (each reading is
#     counted in exactly one period; nothing dropped, nothing double-counted);
#   * /app/decisions.md names the ambiguity and the chosen convention, and the
#     stated convention matches the one detected in the outputs.
#
# Writes 1 to /logs/verifier/reward.txt only when every check passes, else 0.
# The trap guarantees a reward file even if this script dies halfway.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import ast
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime

fails = []


def fail(msg):
    fails.append(msg)


def close(a, b):
    return abs(a - b) <= 1e-7 * max(1.0, abs(b)) + 1e-9


def parse_periods(path):
    with open(path) as fh:
        data = json.load(fh)
    ps = []
    prev_to = None
    for p in data["periods"]:
        pid = p["id"]
        frm = datetime.fromisoformat(p["from"])
        to = datetime.fromisoformat(p["to"])
        if prev_to is not None and frm != prev_to:
            fail("fixture %s: periods are not consecutive" % path)
        prev_to = to
        ps.append((pid, frm, to))
    return ps


def parse_events(path):
    rows = []
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            rows.append((datetime.fromisoformat(r["timestamp"].strip()),
                         float(r["value"])))
    return rows


def expected_totals(periods, events, kind):
    tot = {pid: 0.0 for pid, _, _ in periods}
    for ts, val in events:
        for pid, frm, to in periods:
            if kind == "later":   # half-open [from, to): boundary joins the
                inside = frm <= ts < to   # period that starts at the instant
            else:                 # end-inclusive (from, to]: boundary joins
                inside = frm < ts <= to   # the period that ends at the instant
            if inside:
                tot[pid] += val
                break
    return tot


def assess(got, periods, events, label):
    """Return the detected boundary convention, or None after failing."""
    want = {pid for pid, _, _ in periods}
    gk = set(got.keys())
    if gk != want:
        fail("%s: key set %s != expected %s" %
             (label, sorted(gk), sorted(want)))
        return None
    for pid, _, _ in periods:
        v = got[pid]
        if not isinstance(v, (int, float)):
            fail("%s: value for %r is not a number (%r)" % (label, pid, v))
            return None
    exp_later = expected_totals(periods, events, "later")
    exp_earlier = expected_totals(periods, events, "earlier")
    match_later = all(close(got[k], exp_later[k]) for k in want)
    match_earlier = all(close(got[k], exp_earlier[k]) for k in want)
    if match_later and match_earlier:
        return "both"
    if match_later:
        return "later"
    if match_earlier:
        return "earlier"
    fail("%s: totals match neither boundary convention; got %s" %
         (label, json.dumps(got)))
    fail("%s: half-open [from, to) totals would be %s" %
         (label, json.dumps(exp_later)))
    fail("%s: end-inclusive (from, to] totals would be %s" %
         (label, json.dumps(exp_earlier)))
    return None


# ---- deliverable existence ----
for p in ("/app/aggregate.py", "/app/result.json", "/app/decisions.md"):
    if not os.path.isfile(p):
        fail("missing deliverable " + p)
if not os.path.isfile("/app/aggregate.py"):
    print("FAILURES:")
    for m in fails:
        print("  - " + m)
    print("nothing to grade: /app/aggregate.py does not exist")
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

# ---- aggregate.py constraints: stdlib only, argv-driven, no shipped paths ----
tree = ast.parse(open("/app/aggregate.py").read())
imports = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for a in node.names:
            imports.add(a.name.split(".")[0])
    elif isinstance(node, ast.ImportFrom) and node.module:
        imports.add(node.module.split(".")[0])
bad = sorted(i for i in imports if i not in sys.stdlib_module_names)
if bad:
    fail("aggregate.py imports non-stdlib modules: %s" % bad)
src = open("/app/aggregate.py").read()
if "sys.argv" not in src:
    fail("aggregate.py never reads its argv (must be CLI-driven)")
for hard in ("/app/periods.json", "/app/events.csv", "/app/spec.md"):
    if hard in src:
        fail("aggregate.py hard-codes shipped path " + hard)

# ---- shipped visible inputs must be untouched (pristine sha256) ----
VIS_DIGESTS = {
    "periods.json": "88885fbee4ec43221d8748420cfa23e02b1ed19889e48eec8a5bdabb0023c5e7",
    "events.csv": "2729136f129786680c48b1904bbfc537386a74e910aa3e4e8a81230e0ba4b224",
    "spec.md": "6b63cd88edf359ff2c9e854a66f1f658b0b90ff16e91b99257a1742242e43c55",
}
for name, want in VIS_DIGESTS.items():
    ship = "/app/" + name
    if not os.path.isfile(ship):
        fail("missing shipped input " + ship)
    else:
        got = hashlib.sha256(open(ship, "rb").read()).hexdigest()
        if got != want:
            fail("shipped /app/%s was modified; it must stay byte-identical "
                 "to the original (sha256 %s != %s)" % (name, got, want))

periods = parse_periods("/app/periods.json")
events = parse_events("/app/events.csv")
want_ids = {pid for pid, _, _ in periods}

# ---- delivered result.json ----
try:
    with open("/app/result.json") as fh:
        delivered = json.load(fh)
except Exception as e:
    fail("result.json is not valid JSON: %s" % e)
    delivered = None

convs = []
if delivered is not None:
    c = assess(delivered, periods, events, "delivered result.json (visible)")
    if c == "later":
        convs.append("later")
    elif c == "earlier":
        convs.append("earlier")

# ---- a fresh run of the program on the visible dataset ----
out_vis = "/tmp/wh_vis.json"
r = subprocess.run([sys.executable, "/app/aggregate.py",
                    "/app/periods.json", "/app/events.csv", out_vis],
                   capture_output=True, text=True)
if r.returncode != 0:
    fail("visible rerun of /app/aggregate.py failed: " + r.stderr.strip())
else:
    with open(out_vis) as fh:
        rerun = json.load(fh)
    c = assess(rerun, periods, events, "visible rerun")
    if c == "later":
        convs.append("later")
    elif c == "earlier":
        convs.append("earlier")
    if delivered is not None:
        for pid in want_ids:
            if not close(delivered[pid], rerun[pid]):
                fail("result.json disagrees with a fresh run of the program "
                     "for %r (%r vs %r)" % (pid, delivered[pid], rerun[pid]))

# ---- hidden fixtures ----
hidden_root = "/tests/hidden"
cases = sorted(n for n in os.listdir(hidden_root)
               if os.path.isdir(os.path.join(hidden_root, n)))
if len(cases) < 2:
    fail("expected at least 2 hidden fixtures, found %d" % len(cases))
for case in cases:
    cdir = os.path.join(hidden_root, case)
    pj = os.path.join(cdir, "periods.json")
    ev = os.path.join(cdir, "events.csv")
    if not (os.path.isfile(pj) and os.path.isfile(ev)):
        fail("%s: fixture missing periods.json or events.csv" % case)
        continue
    out = "/tmp/wh_%s.json" % case
    r = subprocess.run([sys.executable, "/app/aggregate.py", pj, ev, out],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("%s: /app/aggregate.py failed: %s" % (case, r.stderr.strip()))
        continue
    try:
        with open(out) as fh:
            got = json.load(fh)
    except Exception as e:
        fail("%s: output is not valid JSON: %s" % (case, e))
        continue
    c = assess(got, parse_periods(pj), parse_events(ev), case)
    if c == "later":
        convs.append("later")
    elif c == "earlier":
        convs.append("earlier")

# ---- convention consistency across all datasets ----
distinct = sorted(set(convs))
if not convs:
    fail("no dataset discriminated the two boundary conventions; "
         "cannot verify internal consistency")
elif len(distinct) > 1:
    fail("boundary convention differs across datasets: %s" % distinct)
else:
    detected = distinct[0]

    # ---- decisions.md ----
    try:
        with open("/app/decisions.md", encoding="utf-8", errors="replace") as fh:
            dec = fh.read()
    except OSError as e:
        fail("cannot read /app/decisions.md: %s" % e)
        dec = ""
    low = dec.lower()
    if len(dec.strip()) < 80:
        fail("decisions.md is too short to be a real decisions document "
             "(%d chars)" % len(dec.strip()))

    RE_AMB = [
        r"boundar", r"exactly\s+at", r"at\s+exactly",
        r"edge\s+case", r"ambiguous", r"unspecified",
        r"not\s+specified", r"not\s+defined", r"silent",
        r"which\s+period", r"open\s+question",
        r"midnight", r"08:00", r"16:00",
        r"between\s+(?:two\s+)?(?:adjacent\s+)?periods?",
    ]
    if not any(re.search(p, low) for p in RE_AMB):
        fail("decisions.md does not name the ambiguity in the specification "
             "(a reading exactly at a period boundary)")

    RE_EARLIER = [
        r"end\s*[- ]?inclusiv\w*",
        r"includ\w*\s+the\s+end\w*",
        r"the\s+end\w*\s+(?:is|was|being)\s+includ\w*",
        r"\(from\s*,\s*to\s*\]|\[from\s*,\s*to\s*\]|"
        r"\(start\s*,\s*end\s*\]|\[start\s*,\s*end\s*\]",
        r"\bclosed\b",
        r"start\s*[- ]?exclusiv\w*",
        r"exclud\w*\s+the\s+start\w*",
        r"(?:earlier|previous|preceding|prior)\s+"
        r"(?:period|bucket|bin|window|interval)",
        r"(?:period|bucket|bin|window|interval)\s+"
        r"(?:that|which|it)\s+(?:just\s+)?(?:ended|finishes|finished)",
    ]
    RE_LATER = [
        r"half\s*[-]?\s*open\w*",
        r"end\s*[- ]?exclusiv\w*",
        r"exclud\w*\s+the\s+end\w*",
        r"the\s+end\w*\s+(?:is|was|being)\s+exclud\w*",
        r"\[from\s*,\s*to\s*\)|\[start\s*,\s*end\s*\)",
        r"start\s*[- ]?inclusiv\w*",
        r"includ\w*\s+the\s+start\w*",
        r"the\s+start\w*\s+(?:is|was|being)\s+includ\w*",
        r"(?:next|following|later|subsequent|new)\s+"
        r"(?:period|bucket|bin|window|interval)",
        r"(?:period|bucket|bin|window|interval)\s+"
        r"(?:that|which|it)\s+(?:just\s+)?(?:starts|started|begins|began)",
    ]

    def kinds_in(text):
        e = [p for p in RE_EARLIER if re.search(p, text)]
        l = [p for p in RE_LATER if re.search(p, text)]
        return e, l

    e_all, l_all = kinds_in(low)
    e_present, l_present = bool(e_all), bool(l_all)

    # A sentence is a *commitment* to one convention only when it states the
    # choice itself.  Sentences that merely describe the alternative (marked
    # with contrast words) or that list both conventions neutrally must not
    # count, or a doc that "chose X" and described "the alternative Y" would
    # look self-contradictory and skip the doc-vs-code check (that bug let a
    # doc stating the opposite convention pass).  The bare word
    # "convention" is therefore not a choice verb: "the end-inclusive
    # convention assigns 08:00 to night" describes, it does not commit.
    CHOICE = re.compile(
        r"\b(chose|chosen|choose|choosing|decided|decision|selected|select|"
        r"adopted|adopt|picked|pick|used?|using|implemented|implementation|"
        r"interpret(?:ed|ation)?|rule|settle[d]?)\b")
    CONTRAST = re.compile(
        r"\b(alternative|alternatively|instead|as\s+opposed\s+to|"
        r"rather\s+than|by\s+contrast|in\s+contrast|the\s+other\b|"
        r"on\s+the\s+other\s+hand)\b")
    NEGATION = re.compile(r"\b(not|no|never|n['’]t|without)\b")
    DIR_MARK = re.compile(
        r"\b(?:rather\s+than|instead\s+of|as\s+opposed\s+to|over\s+the)\b")

    def sides_of(text):
        e = [p for p in RE_EARLIER if re.search(p, text)]
        l = [p for p in RE_LATER if re.search(p, text)]
        return bool(e), bool(l)

    claims = []
    SENT_SPLIT = re.compile(r"(?<=[.!?:])\s*[\n ]+\s*")
    for sent in SENT_SPLIT.split(dec):
        if not CHOICE.search(sent):
            continue
        s = sent.lower()
        e, l = sides_of(s)
        if e != l:
            # single-sided.  Only count it if it is not describing the
            # alternative side.
            if not CONTRAST.search(s):
                claims.append("later" if l else "earlier")
            continue
        if not e:
            continue  # neither side named: not a commitment
        # Both conventions named in one sentence: resolve a directional
        # construction ("X rather than Y", "X over Y") by the clause that
        # holds the choice verb, and a negation ("I did not use the
        # end-inclusive one; I chose half-open") by the unnegated clauses.
        m = DIR_MARK.search(s)
        if m:
            hit = CHOICE.search(s)
            part = (s[:m.start()] if hit and hit.start() < m.start()
                    else s[m.start():])
            pe, pl = sides_of(part)
            if pe != pl:
                claims.append("later" if pl else "earlier")
        elif NEGATION.search(s):
            for cl in re.split(r"[;,:\.\n]+\s*", s):
                if NEGATION.search(cl) or not CHOICE.search(cl):
                    continue
                ce, cl_ = sides_of(cl)
                if ce != cl_:
                    claims.append("later" if cl_ else "earlier")
                    break

    def conv_name(kind):
        return ("half-open [from, to) (boundary to the period that starts "
                "at it)" if kind == "later"
                else "end-inclusive (from, to] (boundary to the period that "
                "ends at it)")

    claim = None
    setc = set(claims)
    if len(setc) == 1:
        claim = setc.pop()
    elif len(setc) > 1:
        fail("decisions.md is self-contradictory about the convention: it "
             "states the %s convention in some places and the %s convention "
             "in others" % (conv_name("earlier"), conv_name("later")))
    elif e_present != l_present:
        claim = "later" if l_present else "earlier"
    else:
        fail("decisions.md never clearly states which convention was "
             "implemented (which side owns a reading taken exactly at a "
             "period boundary); merely touching on both conventions is not "
             "a decision")

    if claim is not None and claim != detected:
        fail("decisions.md states the %s convention but the outputs "
             "implement the %s convention" %
             (conv_name(claim), conv_name(detected)))

# ---- verdict ----
if fails:
    print("FAILURES:")
    for m in fails:
        print("  - " + m)
    print("conventions detected across datasets: %s" % sorted(set(convs)))
    open("/logs/verifier/reward.txt", "w").write("0")
else:
    print("ALL PASS")
    print("boundary convention detected across all datasets: %s"
          % sorted(set(convs)))
    open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY
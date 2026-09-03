#!/bin/bash
# Verifier for tl-briar-entity: audits the XXE remediation deliverables.
#
# Flow:
#   1. immutability: /app/config.json and /app/samples/* must equal the
#      pristine copies shipped under /opt/pristine.
#   2. reads the submitted /app/xxe_audit.json (structure + five entries).
#   3. independently probes the PRISTINE parsers (/opt/pristine/parsers) with
#      hidden payloads (a file-read probe whose secret lives in
#      /tests/hidden, and recursive probes at depths 12 and 14) and requires
#      the submitted audit verdicts to match the probe results exactly —
#      i.e. flagged-vulnerable parsers really were exploitable pre-patch.
#   4. probes the PATCHED parsers (/app/parsers/*.py) with the same hidden
#      payloads: every parser must reject or neutralize the file-read probe
#      and both recursive probes, while still extracting every hidden benign
#      document and every visible sample byte-for-byte as an independent
#      reference extractor does.
#   5. re-runs /app/analyze_xxe.py against the pristine parsers and requires
#      the regenerated audit to be byte-identical to the submitted one (the
#      audit must be a real probe product, not a hand-written file).
# Writes 1/0 to /logs/verifier/reward.txt on every exit path.
set -u
mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt
overall=0
finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
log() { echo "tl-briar-entity verify: $*" >&2; }

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""
RUNPY="python3"

python3 - <<'PYEOF'
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

failures = []

PARSER_PATHS = [
    "/app/parsers/catalog_fetch.py",
    "/app/parsers/directive_loader.py",
    "/app/parsers/plain_text.py",
    "/app/parsers/report_sieve.py",
    "/app/parsers/snippet_extract.py",
]
PARSER_NAMES = sorted(p.rsplit("/", 1)[1] for p in PARSER_PATHS)
ROOT_PATCHED_DIR = "/app/parsers"
ROOT_PRISTINE = "/opt/pristine/parsers"
AUDIT_PATH = "/app/xxe_audit.json"
ANALYZER_PATH = "/app/analyze_xxe.py"
MARKER = "#"
MAX_DEPTH = 6
THRESH = 2 ** MAX_DEPTH          # 64
EXPANDED = MARKER * (THRESH + 1)  # a 65-char run proves expansion > depth 6


def run(py, arg, timeout=60):
    try:
        res = subprocess.run([sys.executable, py, arg],
                             capture_output=True, timeout=timeout)
        return res.returncode, res.stdout, res.stderr
    except Exception as exc:
        failures.append("running %r on %r raised %s" % (py, arg, exc))
        return -1, b"", b""


def read_bytes(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as exc:
        failures.append("cannot read %s: %s" % (path, exc))
        return None


# --- 0. immutable fixtures -----------------------------------------------
for rel in ("config.json",):
    got = read_bytes("/app/" + rel)
    want = read_bytes("/opt/pristine/" + rel)
    if got is not None and want is not None and got != want:
        failures.append("%s differs from the pristine original" % rel)
for sample in sorted(os.listdir("/opt/pristine/samples")):
    got = read_bytes("/app/samples/" + sample)
    want = read_bytes("/opt/pristine/samples/" + sample)
    if got is not None and want is not None and got != want:
        failures.append("samples/%s differs from the pristine original"
                        % sample)

# --- 1. audit deliverable present and well-formed -------------------------
try:
    with open(AUDIT_PATH, encoding="utf-8") as fh:
        audit = json.load(fh)
except Exception as exc:
    failures.append("audit unreadable: %s" % exc)
    audit = None

if audit is not None:
    if not isinstance(audit, dict):
        failures.append("audit is not a JSON object")
        audit = None
    else:
        if audit.get("schema") != "tl-briar-entity/audit/v1":
            failures.append("audit schema mismatch")
        parsers = audit.get("parsers")
        if not isinstance(parsers, list):
            failures.append("audit missing parsers list")
        else:
            names = [e.get("parser") for e in parsers]
            if names != sorted(PARSER_NAMES):
                failures.append("audit must list exactly the five parsers "
                                "in sorted order; got %s" % names)
            else:
                for entry in parsers:
                    if "vulnerable" not in entry or \
                            not isinstance(entry.get("reasons"), list):
                        failures.append("audit entry malformed: %s"
                                        % entry.get("parser"))

# --- 2. hidden probes ------------------------------------------------------
probe_dir = tempfile.mkdtemp(prefix="tl-briar-verify-")
secret_raw = read_bytes("/tests/hidden/secret.txt") or b""
secret = secret_raw.rstrip(b"\r\n")
if not secret:
    failures.append("hidden secret file empty/unreadable")

with open(os.path.join(probe_dir, "secret.txt"), "wb") as fh:
    fh.write(secret + b"\n")
file_probe = os.path.join(probe_dir, "input_f.xml")
with open(file_probe, "w", encoding="utf-8") as fh:
    fh.write('<?xml version="1.0"?>\n'
             '<!DOCTYPE r [<!ENTITY xxe SYSTEM "%s">]>\n'
             '<r>pre &xxe; post</r>\n'
             % Path(os.path.join(probe_dir, "secret.txt")).as_uri())

def rec_probe(depth):
    lines = ['<?xml version="1.0"?>', "<!DOCTYPE deep [",
             '<!ENTITY e0 "%s">' % MARKER]
    for i in range(1, depth + 1):
        lines.append('<!ENTITY e%d "&e%d;&e%d;">' % (i, i - 1, i - 1))
    lines.append("]>")
    lines.append("<deep>&e%d;</deep>" % depth)
    path = os.path.join(probe_dir, "input_r%d.xml" % depth)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return path

rec12 = rec_probe(12)
rec14 = rec_probe(14)


def expand_run(out):
    return 1 if re.search(re.escape(EXPANDED).encode("utf-8"), out) else 0


# --- 3. independent reference extractor (documents the extraction rules) --
PREDEF = {"amp": "&", "lt": "<", "gt": ">", "apos": "'", "quot": '"'}


def doctype_end(src, i):
    n = len(src); quote = None; depth = 0
    while i < n:
        c = src[i]
        if quote:
            if c == quote: quote = None
        elif c in "\"'": quote = c
        elif c == "[": depth += 1
        elif c == "]": depth -= 1
        elif c == ">" and depth <= 0:
            return i
        i += 1
    return n


def declared_entities(src):
    m = re.search(r"<![ \t\r\n]*DOCTYPE\b", src, re.I)
    if not m:
        return {}
    end = doctype_end(src, m.end())
    region = src[m.start():end + 1]
    out = {}
    entity_re = re.compile(
        r"<![ \t\r\n]*ENTITY[ \t\r\n]+([A-Za-z_:][\w:.-]*)"
        r"(?:[ \t\r\n]+(SYSTEM|PUBLIC))?"
        r"[ \t\r\n]*([\"'])(.*?)\3\s*>", re.S)
    for decl in entity_re.finditer(region):
        if decl.group(2) is not None:  # external entity: skipped by parsers
            continue
        out[decl.group(1)] = decl.group(4)
    return out


def decode_refs(seg, ents):
    def ref(m):
        body = m.group(1)
        if body in PREDEF:
            return PREDEF[body]
        if body.startswith("#"):
            num = body[1:]
            return chr(int(num[1:], 16)) if num[:1].lower() == "x" \
                else chr(int(num))
        if body in ents:
            return decode_refs(ents[body], ents)
        return m.group(0)
    return re.sub(r"&([A-Za-z:#][\w:.-]*);", ref, seg)


def extract_text(src):
    ents = declared_entities(src)
    segments = []  # (kind, text, depth_at_capture)
    i, n = 0, len(src)
    depth = 0
    while i < n:
        lt = src.find("<", i)
        if lt < 0:
            segments.append(("plain", src[i:], depth))
            break
        if lt > i:
            segments.append(("plain", src[i:lt], depth))
        if src.startswith("<!--", lt):
            ie = src.find("-->", lt + 4)
            i = len(src) if ie < 0 else ie + 3
        elif src.startswith("<![CDATA[", lt):
            ie = src.find("]]>", lt + 9)
            if ie < 0:
                segments.append(("plain", src[lt:], depth))
                break
            segments.append(("cdata", src[lt + 9:ie], depth))
            i = ie + 3
        elif src.startswith("<?", lt):
            ie = src.find("?>", lt + 2)
            i = len(src) if ie < 0 else ie + 2
        elif re.match(r"<![ \t\r\n]*DOCTYPE\b", src[lt:], re.I):
            i = doctype_end(src, lt + len(
                re.match(r"<![ \t\r\n]*DOCTYPE\b", src[lt:], re.I).group(0))) + 1
        elif src.startswith("<!", lt):
            # other markup declarations (ENTITY/NOTATION/ATTLIST/ELMENT)
            # in the internal subset: skip to the next ">".
            j = src.find(">", lt + 2)
            i = n if j < 0 else j + 1
        elif src.startswith("</", lt):
            j = src.find(">", lt + 2)
            i = n if j < 0 else j + 1
            depth = max(0, depth - 1)
        else:
            # element start tag; self-closing tags change no depth.
            j = src.find(">", lt + 1)
            if j < 0:
                i = n
                depth += 1
            elif src[j - 1] == "/":
                i = j + 1
            else:
                depth += 1
                i = j + 1
    out = []
    for kind, seg, at_depth in segments:
        if kind == "plain" and at_depth >= 1:
            out.append(decode_refs(seg, ents))
        elif kind == "cdata" and at_depth >= 1:
            out.append(seg)
    return "".join(out)


def expected_bytes(doc_path):
    try:
        with open(doc_path, encoding="utf-8") as fh:
            src = fh.read()
    except OSError as exc:
        failures.append("cannot read benign doc %s: %s" % (doc_path, exc))
        return None
    return ("OK " + extract_text(src)).encode("utf-8")


# --- 4. pristine verdicts + audit agreement -------------------------------
audit_by_name = {}
if audit is not None and isinstance(audit, dict):
    for entry in audit.get("parsers", []):
        audit_by_name[entry["parser"]] = entry

for name in PARSER_NAMES:
    pristine = os.path.join(ROOT_PRISTINE, name)
    patched = os.path.join(ROOT_PATCHED_DIR, name)
    if not os.path.isfile(pristine):
        failures.append("pristine copy missing: %s" % pristine)
        continue
    if not os.path.isfile(patched):
        failures.append("deliverable missing: %s" % patched)
        continue

    # independent pre-patch verdict from the hidden probes
    classes = []
    _, f_out, f_err = run(pristine, file_probe)
    if secret in f_out or secret in f_err:
        classes.append("external entity resolution")
    r12_rc, r12_out, _ = run(pristine, rec12)
    if r12_rc == 0 and expand_run(r12_out):
        classes.append("recursive entity expansion")
    classes = sorted(set(classes))

    entry = audit_by_name.get(name)
    if entry is None:
        failures.append("audit missing entry for %s" % name)
        continue
    if entry.get("vulnerable") != bool(classes):
        failures.append("%s: audit says vulnerable=%s but the pristine "
                        "parser probes show %s"
                        % (name, entry.get("vulnerable"), classes))
    if sorted(entry.get("reasons", [])) != classes:
        failures.append("%s: audit reasons %s do not match probe classes %s"
                        % (name, entry.get("reasons"), classes))

    # pristine parsers must also handle the visible samples (sanity)
    for sample in sorted(os.listdir("/opt/pristine/samples")):
        path = "/app/samples/" + sample
        rc, out, _ = run(pristine, path)
        want = expected_bytes(path)
        if want is not None and (rc != 0 or out not in (want, want + b"\n")):
            failures.append("%s: pristine run on visible %s mismatch"
                            % (name, sample))

    # patched parsers: reject/neutralize every hidden probe
    _, p_out, p_err = run(patched, file_probe)
    if secret in p_out or secret in p_err:
        failures.append("%s: patched parser still leaks the file-read "
                        "probe" % name)
    for depth, probe in ((12, rec12), (14, rec14)):
        rc, out, _ = run(patched, probe)
        if rc == 0 and expand_run(out):
            failures.append("%s: patched parser still expands the "
                            "recursive probe (depth %d)" % (name, depth))

    # patched parsers must still pass every hidden benign input + visible
    for doc in (["/tests/hidden/benign_a.xml",
                 "/tests/hidden/benign_b.xml",
                 "/tests/hidden/benign_c.xml",
                 "/tests/hidden/benign_d.xml"]
                + sorted("/app/samples/" + s
                         for s in os.listdir("/opt/pristine/samples"))):
        rc, out, _ = run(patched, doc)
        want = expected_bytes(doc)
        if want is None:
            continue
        if rc != 0:
            failures.append("%s: patched parser rejected benign %s (rc=%d)"
                            % (name, doc, rc))
        elif out not in (want, want + b"\n"):
            failures.append("%s: patched parser output for %s differs "
                            "from reference (%r)"
                            % (name, doc, out[:80]))

# --- 5. the audit must be regenerable from the analyzer against pristine --
if os.path.isfile(ANALYZER_PATH):
    regen = os.path.join(probe_dir, "regen-audit.json")
    try:
        res = subprocess.run(
            [sys.executable, ANALYZER_PATH,
             "--parsers-dir", ROOT_PRISTINE,
             "--out", regen, "--max-depth", "6"],
            capture_output=True, timeout=120)
    except Exception as exc:
        failures.append("analyzer run raised %s" % exc)
        res = None
    if res is not None and res.returncode != 0:
        failures.append("analyzer exited %d: %s"
                        % (res.returncode,
                           res.stderr.decode("utf-8", "replace")[:200]))
    else:
        got = read_bytes(regen)
        want = read_bytes(AUDIT_PATH)
        if got is not None and want is not None and got != want:
            failures.append("regenerated audit differs from submitted "
                            "/app/xxe_audit.json")

    # The analyzer must genuinely probe: pointing it at the (already clean)
    # patched parsers must report every parser as not vulnerable. A fixed
    # hardcoded dumper would keep echoing the vulnerable verdicts and fail.
    patched_state = os.path.join(probe_dir, "patched-state-audit.json")
    try:
        res2 = subprocess.run(
            [sys.executable, ANALYZER_PATH,
             "--parsers-dir", ROOT_PATCHED_DIR,
             "--out", patched_state, "--max-depth", "6"],
            capture_output=True, timeout=120)
    except Exception as exc:
        failures.append("analyzer (patched-state) run raised %s" % exc)
        res2 = None
    if res2 is not None and res2.returncode == 0:
        try:
            with open(patched_state, encoding="utf-8") as fh:
                state = json.load(fh)
            for entry in state.get("parsers", []):
                if entry.get("vulnerable", False):
                    failures.append(
                        "analyzer still flags patched %s as vulnerable "
                        "(analyzer does not reflect real behavior)"
                        % entry.get("parser"))
        except Exception as exc:
            failures.append("patched-state audit unreadable: %s" % exc)
    elif res2 is not None:
        failures.append("analyzer (patched-state) exited %d"
                        % res2.returncode)
else:
    failures.append("deliverable missing: %s" % ANALYZER_PATH)

print("verify failures: %d" % len(failures))
for f in failures:
    print(" -", f)
sys.exit(1 if failures else 0)
PYEOF

if [ $? -eq 0 ]; then overall=1; fi
finalize_reward
exit 0
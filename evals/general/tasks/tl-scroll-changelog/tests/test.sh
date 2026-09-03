#!/bin/bash
#
# tl-scroll-changelog verifier.
# Executes the deliverable CLI /app/changelogger.py on the visible repository
# state and on hidden repo states, recomputing expected bumps.json + byte-exact
# CHANGELOG.md content with an INDEPENDENT reference implementation (so a
# visible-hardcoded deliverable fails the hidden states). Also probes the
# documented error paths. Writes reward (0/1) to /logs/verifier/reward.txt on
# every exit path via an EXIT trap.
set -u

mkdir -p /logs/verifier
TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "tl-scroll-changelog verify: $*" >&2; }

if [ ! -f /app/changelogger.py ]; then
  overall=0; msgs="$msgs missing:/app/changelogger.py"
fi

if [ "$overall" = "1" ]; then
  if $TIMEOUT_CMD 120 python3 - <<'PY'
import json, os, re, subprocess, sys, tempfile
from pathlib import Path

CLI = "/app/changelogger.py"
VISIBLE_STATE = "/app/repo_state"
VISIBLE_DATE = "2025-06-15"
# The delivered visible outputs (checked directly, then re-verified by re-run):
DELIV_BUMPS = "/app/release/bumps.json"
DELIV_CLS = [
    "/app/release/core/CHANGELOG.md",
    "/app/release/app/CHANGELOG.md",
    "/app/release/tools/CHANGELOG.md",
]
HIDDEN_ROOT = "/tests/hidden"
HIDDEN_DATES = ["2025-09-14", "2025-09-15", "2025-09-16", "2025-09-17"]

failures = []


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kw)
    except Exception as exc:
        failures.append("running %r raised %s" % (cmd, exc))
        return None


# ---------------------------------------------------------------------------
# Independent reference: recompute bumps + changelog text from a state dir
# using only the documented rules (no shared code with the deliverable).
# ---------------------------------------------------------------------------
SECTION_FOR = {
    "feat": "Added",
    "fix": "Fixed",
    "refactor": "Changed", "perf": "Changed", "test": "Changed",
    "style": "Changed", "build": "Changed", "ci": "Changed",
    "revert": "Changed",
    "docs": None, "chore": None,
}
STRENGTH = {"none": 0, "patch": 1, "minor": 2, "major": 3}
STRENGTH_FOR = {
    "feat": "minor",
    "fix": "patch", "refactor": "patch", "perf": "patch", "test": "patch",
    "style": "patch", "build": "patch", "ci": "patch", "revert": "patch",
    "docs": "none", "chore": "none",
}


def want_bump(ctype, breaking):
    if breaking:
        return "major", SECTION_FOR[ctype]
    return STRENGTH_FOR[ctype], SECTION_FOR[ctype]


def parse_header(first_line):
    """(type, scope|None, breaking|False, description) or None per spec."""
    ln = first_line
    if not ln.strip():
        return None
    head, sep, rest = ln.partition(":")
    if not sep:
        return None
    if not rest or rest[0] not in " \t":
        return None                      # need >=1 space after ':'
    desc = rest.strip()
    if not desc:
        return None
    breaking = False
    scope = None
    # canonical heads: type, type!, type(scope), type(scope)!, type!(scope)
    m = re.fullmatch(r"([a-z]+)(?:\(([a-z0-9_-]+)\))?(!)", head)
    if m:
        ctype, scope, _bang = m.groups()
        breaking = True
    else:
        m = re.fullmatch(r"([a-z]+)(?:\(([a-z0-9_-]+)\))?", head)
        if not m:
            m = re.fullmatch(r"([a-z]+)!\(([a-z0-9_-]+)\)", head)
            if not m:
                return None
            ctype, scope = m.groups()
            breaking = True
        else:
            ctype, scope = m.groups()
    if ctype not in SECTION_FOR:
        return None
    return ctype, scope, breaking, desc


def load_state(state_dir):
    sd = Path(state_dir)
    pkgs = json.loads((sd / "packages.json").read_text())
    tag_obj = json.loads((sd / "last_tag.json").read_text())
    commits = []
    for line in (sd / "commits.jsonl").read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        h, m, fs = obj.get("hash"), obj.get("message"), obj.get("files")
        if not (isinstance(h, str) and isinstance(m, str) and isinstance(fs, list)):
            continue
        commits.append((h, m, [f for f in fs if isinstance(f, str)]))
    return pkgs, tag_obj["tag"], commits


def compute(state_dir, date):
    pkgs, tag, commits = load_state(state_dir)
    per_pkg = {name: [] for name in pkgs}
    for h, msg, files in commits:
        lines = msg.split("\n")
        if not lines:
            continue
        parsed = parse_header(lines[0])
        if parsed is None:
            continue
        ctype, scope, breaking, desc = parsed
        breaking = breaking or any(
            ln.strip().startswith("BREAKING CHANGE:") for ln in lines[1:]
        )
        strength, section = want_bump(ctype, breaking)
        if scope is not None:
            if scope not in pkgs:
                continue
            targets = [scope]
        else:
            targets = []
            for f in files:
                best, best_len = None, -1
                for name, spec in pkgs.items():
                    pref = spec["path"]
                    if f.startswith(pref) and len(pref) > best_len:
                        best, best_len = name, len(pref)
                if best is not None and best not in targets:
                    targets.append(best)
            if not targets:
                continue
        for name in targets:
            per_pkg[name].append((h, desc, section, strength))

    bumps, changelogs = {}, {}
    for name in sorted(pkgs):
        entries = per_pkg[name]
        if not entries:
            continue
        best = "none"
        for _h, _d, _s, st in entries:
            if STRENGTH[st] > STRENGTH[best]:
                best = st
        if best == "none":
            continue
        x, y, z = (int(p) for p in pkgs[name]["version"].split("."))
        new = {"major": "%d.0.0" % (x + 1),
               "minor": "%d.%d.0" % (x, y + 1),
               "patch": "%d.%d.%d" % (x, y, z + 1)}[best]
        bumps[name] = {"from": pkgs[name]["version"], "to": new, "bump": best}
        blocks = ["# %s Changelog" % name, "", "## [%s] - %s" % (new, date), "",
                  "Previous release: %s" % tag]
        for sec in ("Added", "Fixed", "Changed"):
            rows = [(h, d) for (h, d, s, _st) in entries if s == sec]
            if not rows:
                continue
            blocks += ["", "### %s" % sec]
            for h, d in rows:
                blocks.append("- %s (%s)" % (d, h[:7]))
        changelogs[name] = "\n".join(blocks) + "\n"
    return bumps, changelogs


def check_outdir(out_dir, ref_bumps, ref_cls, label):
    out_dir = Path(out_dir)
    try:
        got_bumps = json.loads((out_dir / "bumps.json").read_text())
    except Exception as exc:
        failures.append("%s: bumps.json unreadable (%s)" % (label, exc))
        return
    if got_bumps != ref_bumps:
        failures.append("%s: bumps.json mismatch (got %r want %r)"
                        % (label, got_bumps, ref_bumps))
    expected = {"bumps.json"}
    expected |= {"%s/CHANGELOG.md" % n for n in ref_cls}
    actual = set()
    if out_dir.is_dir():
        for p in sorted(out_dir.rglob("*")):
            if p.is_file():
                actual.add(str(p.relative_to(out_dir)))
    if actual != expected:
        failures.append("%s: output file set mismatch (got %r want %r)"
                        % (label, sorted(actual), sorted(expected)))
    for name, want_text in ref_cls.items():
        path = out_dir / name / "CHANGELOG.md"
        try:
            got_bytes = path.read_bytes()
        except OSError as exc:
            failures.append("%s: cannot read %s (%s)" % (label, path, exc))
            continue
        if got_bytes != want_text.encode("utf-8"):
            failures.append("%s: %s/CHANGELOG.md bytes differ" % (label, name))


def run_cli(state_dir, date, out_dir):
    if os.path.exists(out_dir):
        shutil_rmtree(out_dir)
    return run(["python3", CLI, state_dir, "--date", date, "--out", out_dir])


def shutil_rmtree(p):
    import shutil
    shutil.rmtree(p, ignore_errors=True)


# --- 1. Visible deliverables must exist and equal the independent recompute.
if not os.path.isfile(DELIV_BUMPS):
    failures.append("missing deliverable %s" % DELIV_BUMPS)
for p in DELIV_CLS:
    if not os.path.isfile(p):
        failures.append("missing deliverable %s" % p)
try:
    ref_bumps, ref_cls = compute(VISIBLE_STATE, VISIBLE_DATE)
    if not ref_cls:
        failures.append("visible reference produced no changelogs")
    check_outdir("/app/release", ref_bumps, ref_cls, "deliverable")
except Exception as exc:
    failures.append("visible reference computation failed: %s" % exc)
    ref_bumps, ref_cls = {}, {}

# --- 2. Re-run the deliverable CLI on the visible state (fresh out dir).
r = run_cli(VISIBLE_STATE, VISIBLE_DATE, "/tmp/tlsc_visible_rerun")
if r is None or r.returncode != 0:
    failures.append("visible CLI re-run failed (exit %s)" % (r.returncode if r else "?"))
else:
    check_outdir("/tmp/tlsc_visible_rerun", ref_bumps, ref_cls, "visible-rerun")

# --- 3. Hidden repo states: CLI must generalize to unseen data/shapes.
hidden_dir = Path(HIDDEN_ROOT)
states = sorted(p for p in hidden_dir.iterdir() if p.is_dir() and p.name.startswith("state_"))
if len(states) < 3:
    failures.append("fewer than 3 hidden states present")
for i, state_dir in enumerate(states):
    date = HIDDEN_DATES[i % len(HIDDEN_DATES)]
    try:
        hb, hc = compute(str(state_dir / "repo_state"), date)
    except Exception as exc:
        failures.append("hidden %s: reference computation failed: %s" % (state_dir.name, exc))
        continue
    out_dir = "/tmp/tlsc_hidden_%d" % i
    r = run_cli(str(state_dir / "repo_state"), date, out_dir)
    if r is None or r.returncode != 0:
        failures.append("hidden %s: CLI run failed (exit %s)"
                        % (state_dir.name, r.returncode if r else "?"))
        continue
    check_outdir(out_dir, hb, hc, "hidden:%s" % state_dir.name)

# --- 4. Documented error paths must exit nonzero (never silently succeed).
tmp = tempfile.mkdtemp(prefix="tlsc_err")
# 4a: repo state missing packages.json
d1 = Path(tmp) / "nopkgs"
d1.mkdir()
(d1 / "last_tag.json").write_text('{"tag": "x"}')
(d1 / "commits.jsonl").write_text("")
r = run_cli(str(d1), "2025-09-14", str(Path(tmp) / "o1"))
if r is None or r.returncode == 0:
    failures.append("error-path: missing packages.json must exit nonzero")
# 4b: malformed last_tag.json
d2 = Path(tmp) / "badtag"
d2.mkdir()
(d2 / "packages.json").write_text('{"p": {"path": "p/", "version": "1.0.0"}}')
(d2 / "last_tag.json").write_text("not json at all")
(d2 / "commits.jsonl").write_text("")
r = run_cli(str(d2), "2025-09-14", str(Path(tmp) / "o2"))
if r is None or r.returncode == 0:
    failures.append("error-path: malformed last_tag.json must exit nonzero")
# 4c: bad --date format
r = run_cli(VISIBLE_STATE, "20250601", str(Path(tmp) / "o3"))
if r is None or r.returncode == 0:
    failures.append("error-path: malformed --date must exit nonzero")

print("tl-scroll-changelog verify failures:", failures)
sys.exit(1 if failures else 0)
PY
  then
    :
  else
    overall=0; msgs="$msgs python-verifier-failed"
  fi
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0
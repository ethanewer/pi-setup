#!/usr/bin/env bash
#
# Verifier for marlin-berth: ENFORCES the no-modify rule on the lists fixture,
# then EXECUTES the deliverable /app/setup.sh on the visible fixture and on
# every hidden list file, proving via postfix's own tooling (postconf, postmap
# -q, postalias -q) that the CANONICAL configuration at
# /etc/postfix/virtual_lists is honored -- including after a full state reset
# (map file, databases, main.cf setting and managed aliases all removed).
# Writes REWARD (0/1) to /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

if python3 - <<'PY'
import hashlib, json, shlex, subprocess, sys

SETUP = "/app/setup.sh"
REPORT = "/app/list_report.json"
VISIBLE_LISTS = "/app/fixtures/lists.tsv"
PRISTINE_LISTS_SHA = "2e6e60f7a1f3414f9e3a9f24c238695eec4c80492f0e6de31d61e6e1a882e8ec"
MAP = "/etc/postfix/virtual_lists"
BEGIN, END = "# BEGIN gullwing-lists", "# END gullwing-lists"

failures = []


def run(cmd, timeout=60):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def parse_map_file(path):
    entries = {}
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                raise ValueError("bad map line: %r" % line)
            entries[parts[0].strip()] = parts[1].strip()
    return entries


def reset_state():
    """Remove every trace of the canonical config so setup.sh must rebuild it."""
    run("postconf -X virtual_alias_maps || true")
    if "virtual_lists" in (run("postconf -h virtual_alias_maps").stdout or ""):
        run("postconf -e 'virtual_alias_maps ='")
    run("rm -f %s %s.db /etc/aliases.db /etc/aliases.dir /etc/aliases.pag"
        % (shlex.quote(MAP), shlex.quote(MAP)))
    try:
        lines = open("/etc/aliases", encoding="utf-8").readlines()
    except FileNotFoundError:
        lines = []
    out, in_block = [], False
    for line in lines:
        if line.strip() == BEGIN:
            in_block = True
            continue
        if line.strip() == END:
            in_block = False
            continue
        if not in_block:
            out.append(line)
    with open("/etc/aliases", "w", encoding="utf-8") as fh:
        fh.writelines(out)


def check_installed(expected, label):
    # main.cf declares and honors the canonical map
    r = run("postconf -h virtual_alias_maps")
    if r is None or r.returncode != 0:
        failures.append("%s: postconf failed" % label)
        return
    if "hash:%s" % MAP not in r.stdout:
        failures.append("%s: main.cf does not declare hash:%s (got %r)"
                        % (label, MAP, r.stdout.strip()[:120]))
        return
    # canonical map file content
    try:
        entries = parse_map_file(MAP)
    except FileNotFoundError:
        failures.append("%s: canonical map %s missing" % (label, MAP))
        return
    except Exception as exc:
        failures.append("%s: canonical map unparsable: %s" % (label, exc))
        return
    if entries != expected["map"]:
        failures.append("%s: canonical map mismatch (wrong path content)" % label)
        return
    # the built map database is actually honored by postfix tooling
    for addr, target in expected["map"].items():
        r = run("postmap -q %s hash:%s" % (shlex.quote(addr), shlex.quote(MAP)))
        if r is None or r.returncode != 0 or r.stdout.strip() != target:
            failures.append("%s: postmap -q %s != %r (got %r)"
                            % (label, addr, target, (r.stdout if r else "")[:80]))
    # aliases database honors the managed entries
    for localpart, target in expected.get("aliases", {}).items():
        r = run("postalias -q %s /etc/aliases" % shlex.quote(localpart))
        if r is None or r.returncode != 0 or r.stdout.strip() != target:
            failures.append("%s: postalias -q %s != %r (got %r)"
                            % (label, localpart, target, (r.stdout if r else "")[:80]))
    # pre-existing aliases outside the managed block still work
    r = run("postalias -q postmaster /etc/aliases")
    if r is None or not r.stdout.strip():
        failures.append("%s: postmaster alias no longer resolves" % label)
    # local accounts exist
    for acct in expected.get("accounts", []):
        if run("getent passwd %s" % shlex.quote(acct)).returncode != 0:
            failures.append("%s: local account %r missing" % (label, acct))
    # report deliverable
    try:
        report = json.load(open(REPORT))
    except FileNotFoundError:
        failures.append("%s: missing %s" % (label, REPORT))
        return
    except Exception as exc:
        failures.append("%s: %s unreadable: %s" % (label, REPORT, exc))
        return
    if report.get("map_path") != expected["map_path"]:
        failures.append("%s: report map_path wrong" % label)
    if report.get("lists") != expected["report"]["lists"]:
        failures.append("%s: report lists mismatch" % label)


def run_setup(lists_file):
    r = run("bash %s %s" % (shlex.quote(SETUP), shlex.quote(lists_file)), timeout=120)
    if r is None or r.returncode != 0:
        failures.append("setup.sh failed on %s: %s"
                        % (lists_file, (r.stderr if r else "timeout")[-300:]))
        return False
    return True


# --- no-modify guard on the visible fixture -------------------------------
try:
    h = hashlib.sha256(open(VISIBLE_LISTS, "rb").read()).hexdigest()
    if h != PRISTINE_LISTS_SHA:
        failures.append("lists.tsv was modified (no-modify rule)")
except FileNotFoundError:
    failures.append("missing /app/fixtures/lists.tsv")

# --- visible case ----------------------------------------------------------
if not failures:
    if not run("test -f %s" % shlex.quote(SETUP)).returncode == 0:
        failures.append("missing /app/setup.sh")
    try:
        expected = json.load(open("/tests/expected.json"))
    except Exception as exc:
        failures.append("visible expected unreadable: %s" % exc)
        expected = None
    if expected is not None:
        if run_setup(VISIBLE_LISTS):
            check_installed(expected, "visible")
        # idempotency: a second run must succeed and keep everything correct
        if run_setup(VISIBLE_LISTS):
            check_installed(expected, "visible-rerun")
        # from-scratch: with all canonical state wiped, one run reinstalls it
        reset_state()
        if run_setup(VISIBLE_LISTS):
            check_installed(expected, "visible-reset")

# --- hidden cases (same format, different addresses/targets/accounts) ------
if not failures:
    import os
    hidden_dir = "/tests/hidden"
    cases = 0
    if os.path.isdir(hidden_dir):
        for name in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, name)
            lists_file = os.path.join(base, "lists.tsv")
            if not os.path.isfile(lists_file):
                continue
            try:
                want = json.load(open(os.path.join(base, "expected.json")))
            except Exception as exc:
                failures.append("hidden '%s' expected unreadable: %s" % (name, exc))
                continue
            reset_state()
            if run_setup(lists_file):
                check_installed(want, "hidden-%s" % name)
            cases += 1
        if cases < 2:
            failures.append("expected >=2 hidden cases, saw %d" % cases)
    else:
        failures.append("no hidden cases directory")

# --- leave the visible scenario installed ----------------------------------
if not failures:
    reset_state()
    run_setup(VISIBLE_LISTS)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY
then
  printf 1 > /logs/verifier/reward.txt
else
  printf 0 > /logs/verifier/reward.txt
fi
exit 0
#!/usr/bin/env python3
"""pipit-archive verifier core (hidden from the agent at solve time).

Implements the documented persistence-artifact-scanning rules as an
INDEPENDENT reference analyzer (class-based, different decomposition from the
deliverable), materializes three hidden rootfs trees at /tmp, executes the
deliverable /app/scan_persistence.py against the visible tree and each hidden
tree, and compares the parsed JSON exactly against this reference recompute.
Also enforces byte-for-byte idempotency (two runs -> identical report bytes)
and the documented exit-code contract.

The full flow is driven from test.sh; this script exits 0 only when every
check passes. The reward gate lives in test.sh.
"""
import json
import os
import re
import shutil
import subprocess
import sys

SCANNER = "/app/scan_persistence.py"
VISIBLE_REPORT = "/app/findings.json"
VISIBLE_ROOT = "/app/rootfs"

# ---------------------------------------------------------------------------
# Documented rule constants (must match the contract text).
# ---------------------------------------------------------------------------
_TIME_RE = re.compile(r"^[0-9A-Za-z*,/\-?]+$")
_USER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")
_CRON_ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\s*=")
_SHELL_ENV_RE = re.compile(r"^(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=\s*\S*$")
_AT_NAME_RE = re.compile(r"^[0-9a-fA-F]{6,}$")
_UNIT_EXTS = (".service", ".timer", ".socket", ".path", ".target",
              ".mount", ".automount", ".swap", ".slice")
_SHELL_KEYWORDS = ("if", "then", "else", "elif", "fi", "for", "while",
                   "until", "do", "done", "case", "esac", "in",
                   "select", "function", "time")

_SYSTEMD_SUBDIRS = ("etc/systemd/system", "usr/lib/systemd/system",
                    "lib/systemd/system", "run/systemd/units")


def _blank_or_comment(text):
    return text == "" or text[0] in "#;"


class ReferenceAnalyzer:
    """Recomputes the documented findings for a rootfs tree."""

    def __init__(self, root):
        self.root = root
        self.allow = self._load_allowlist(root)

    # -- helpers ------------------------------------------------------------
    def _load_allowlist(self, root):
        path = os.path.join(root, "etc", "persistence-allowlist.json")
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            data = {}
        if not isinstance(data, dict):
            data = {}
        out = {}
        for key, value in data.items():
            if isinstance(value, list):
                out[key] = set(value)
        return out

    @staticmethod
    def _lines(path):
        """1-based (lineno, stripped, raw) tuples; unreadable -> empty."""
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            return []
        result = []
        for idx, raw in enumerate(text.split("\n")):
            if raw.endswith("\r"):
                raw = raw[:-1]
            result.append((idx + 1, raw.strip(), raw))
        return result

    def _allowlisted(self, kind, key):
        return kind in self.allow and key in self.allow[kind]

    # -- per-kind extraction ------------------------------------------------
    def cron_entries(self, path, kind):
        found = []
        for lineno, line, raw in self._lines(path):
            if _blank_or_comment(line):
                continue
            if _CRON_ENV_RE.match(line):
                continue
            tokens = line.split()
            if not tokens:
                continue
            if tokens[0].startswith("@"):
                remainder = tokens[1:]
            elif len(tokens) >= 6 and all(_TIME_RE.fullmatch(t)
                                          for t in tokens[:5]):
                remainder = tokens[5:]
            else:
                continue
            if len(remainder) >= 2 and _USER_RE.fullmatch(remainder[0]):
                command = " ".join(remainder[1:])
            else:
                command = " ".join(remainder)
            command = command.strip()
            if command == "":
                continue
            if self._allowlisted(kind, command):
                status, evidence = "allowlisted", "allowlisted entry"
            elif command.split()[0].startswith("#"):
                status, evidence = "disabled", line
            else:
                status, evidence = "active", line
            found.append({"location_kind": kind, "path": path,
                          "line_or_key": lineno, "status": status,
                          "evidence": evidence})
        return found

    def systemd_findings(self):
        found = []
        for sub in _SYSTEMD_SUBDIRS:
            top = os.path.join(self.root, sub)
            if not os.path.isdir(top):
                continue
            for dirpath, _dirs, names in os.walk(top):
                for name in sorted(names):
                    if not name.endswith(_UNIT_EXTS):
                        continue
                    full = os.path.join(dirpath, name)
                    if os.path.islink(full):
                        continue
                    section = None
                    install_ok = False
                    for _n, line, _r in self._lines(full):
                        if line.startswith("[") and line.endswith("]"):
                            section = line.lower()
                            continue
                        if section != "[install]" or _blank_or_comment(line):
                            continue
                        left, sep, right = line.partition("=")
                        value = right.split("#", 1)[0].strip()
                        if sep and value and left.strip() in ("WantedBy",
                                                              "RequiredBy"):
                            install_ok = True
                            break
                    if self._allowlisted("systemd_unit", name):
                        status, evidence = "allowlisted", "allowlisted entry"
                    elif install_ok:
                        status = "active"
                        evidence = "active via [Install]"
                    else:
                        status = "disabled"
                        evidence = "disabled: no [Install] WantedBy/RequiredBy"
                    found.append({"location_kind": "systemd_unit",
                                  "path": full, "line_or_key": name,
                                  "status": status,
                                  "evidence": evidence})
        return found

    def rc_local_findings(self):
        found = []
        path = os.path.join(self.root, "etc", "rc.local")
        for lineno, line, raw in self._lines(path):
            if _blank_or_comment(line):
                continue
            if line.split()[0] == "exit":
                break
            if self._allowlisted("rc_local", line):
                status, evidence = "allowlisted", "allowlisted entry"
            else:
                status, evidence = "active", line
            found.append({"location_kind": "rc_local", "path": path,
                          "line_or_key": lineno, "status": status,
                          "evidence": evidence})
        return found

    def shell_rc_files(self):
        files = [os.path.join(self.root, "etc", "profile"),
                 os.path.join(self.root, "etc", "bash.bashrc")]
        prof_dir = os.path.join(self.root, "etc", "profile.d")
        try:
            with os.scandir(prof_dir) as it:
                for entry in it:
                    if entry.is_file() and entry.name.endswith(".sh"):
                        files.append(entry.path)
        except OSError:
            pass
        for basename in (".bashrc", ".profile"):
            candidate = os.path.join(self.root, "root", basename)
            if os.path.isfile(candidate):
                files.append(candidate)
        home = os.path.join(self.root, "home")
        try:
            with os.scandir(home) as it:
                for entry in it:
                    if not entry.is_dir():
                        continue
                    for basename in (".bashrc", ".profile", ".bash_profile"):
                        candidate = os.path.join(entry.path, basename)
                        if os.path.isfile(candidate):
                            files.append(candidate)
        except OSError:
            pass
        return files

    def shell_rc_findings(self):
        found = []
        for path in self.shell_rc_files():
            for lineno, line, raw in self._lines(path):
                if _blank_or_comment(line):
                    continue
                first = line.split()[0]
                if first in _SHELL_KEYWORDS:
                    continue
                if first[0] in "[!({":
                    continue
                if _SHELL_ENV_RE.match(line):
                    continue
                if self._allowlisted("shell_rc", line):
                    status, evidence = "allowlisted", "allowlisted entry"
                else:
                    status, evidence = "active", line
                found.append({"location_kind": "shell_rc", "path": path,
                              "line_or_key": lineno, "status": status,
                              "evidence": evidence})
        return found

    def ld_preload_findings(self):
        found = []
        path = os.path.join(self.root, "etc", "ld.so.preload")
        for lineno, line, raw in self._lines(path):
            if _blank_or_comment(line):
                continue
            if self._allowlisted("ld_preload", line):
                status, evidence = "allowlisted", "allowlisted entry"
            else:
                status, evidence = "active", line
            found.append({"location_kind": "ld_preload", "path": path,
                          "line_or_key": lineno, "status": status,
                          "evidence": evidence})
        return found

    def at_findings(self):
        found = []
        for sub in ("var/spool/at", "var/spool/cron/atjobs"):
            directory = os.path.join(self.root, sub)
            try:
                with os.scandir(directory) as it:
                    for entry in it:
                        if not entry.is_file():
                            continue
                        if not _AT_NAME_RE.fullmatch(entry.name):
                            continue
                        if self._allowlisted("at_job", entry.name):
                            status, evidence = "allowlisted", \
                                "allowlisted entry"
                        else:
                            status, evidence = "active", "at-job spool file"
                        found.append({"location_kind": "at_job",
                                      "path": entry.path,
                                      "line_or_key": entry.name,
                                      "status": status,
                                      "evidence": evidence})
            except OSError:
                pass
        return found

    # -- entry point --------------------------------------------------------
    def report(self):
        findings = []
        cron_dirs = (os.path.join(self.root, "etc", "cron.d"),)
        try:
            with os.scandir(cron_dirs[0]) as it:
                for entry in it:
                    if entry.is_file():
                        findings.extend(
                            self.cron_entries(entry.path, "cron.d"))
        except OSError:
            pass
        crontab_files = [os.path.join(self.root, "etc", "crontab")]
        crontab_dir = os.path.join(self.root, "var", "spool", "cron",
                                   "crontabs")
        try:
            with os.scandir(crontab_dir) as it:
                for entry in it:
                    if entry.is_file():
                        crontab_files.append(entry.path)
        except OSError:
            pass
        for path in crontab_files:
            if os.path.isfile(path):
                findings.extend(self.cron_entries(path, "crontab"))

        findings.extend(self.systemd_findings())
        findings.extend(self.rc_local_findings())
        findings.extend(self.shell_rc_findings())
        findings.extend(self.ld_preload_findings())
        findings.extend(self.at_findings())

        findings.sort(key=lambda f: (f["location_kind"], f["path"],
                                     str(f["line_or_key"])))
        return {"root": self.root, "findings": findings}


# ---------------------------------------------------------------------------
# Hidden fixture builders (deterministic; rebuilt fresh on every run).
# ---------------------------------------------------------------------------

def write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def build_mixa(root):
    """Symlinked cron dir + mixed artifact spread + own allowlist."""
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(root)
    # cron.d is a symlink to ../data/cronjobs; files report under etc/cron.d
    os.makedirs(os.path.join(root, "etc"))
    os.makedirs(os.path.join(root, "data", "cronjobs"))
    write(os.path.join(root, "data", "cronjobs", "rot-1"),
          "*/7 * * * * root /opt/ferry/qr-beam\n"
          "45 23 * * * root # ferry relay on standby\n")
    write(os.path.join(root, "data", "cronjobs", "decoy"),
          "# scheduled archive\nSHELL=/bin/sh\n")
    os.symlink("../data/cronjobs", os.path.join(root, "etc", "cron.d"))

    write(os.path.join(root, "etc", "crontab"),
          "SHELL=/bin/sh\n"
          "10 4 * * * root /opt/ferry/qr-beam\n")

    os.makedirs(os.path.join(root, "run", "systemd", "units"))
    write(os.path.join(root, "run", "systemd", "units", "ferry-beam.service"),
          "[Unit]\nDescription=Ferry beam\n\n[Service]\n"
          "ExecStart=/opt/ferry/qr-beam --daemon\n\n[Install]\n"
          "WantedBy=multi-user.target\n")
    os.makedirs(os.path.join(root, "etc", "systemd", "system"))
    write(os.path.join(root, "etc", "systemd", "system", "quiet.service"),
          "[Unit]\nDescription=Quiet helper\n\n[Service]\n"
          "ExecStart=/usr/local/bin/quiet\n\n[Install]\n"
          "# WantedBy=multi-user.target\n")

    write(os.path.join(root, "etc", "rc.local"),
          "#!/bin/sh\n"
          "/opt/ferry/spark sync\n"
          "exit 0\n"
          "/opt/ferry/sleeper &\n")

    write(os.path.join(root, "etc", "ld.so.preload"),
          "/lib/ferry/libbridge.so\n"
          "# /opt/ferry/libold.so\n")

    os.makedirs(os.path.join(root, "home", "user2"))
    write(os.path.join(root, "home", "user2", ".bashrc"),
          "nohup /opt/ferry/lift >/dev/null 2>&1 &\n"
          "export EDITOR=nano\n")

    os.makedirs(os.path.join(root, "var", "spool", "at"))
    write(os.path.join(root, "var", "spool", "at", "f1e2d3c4b5a6"),
          "# V2\n/opt/ferry/render --once\n")

    write(os.path.join(root, "etc", "persistence-allowlist.json"),
          json.dumps({
              "cron.d": ["/opt/ferry/qr-beam"],
              "crontab": ["/opt/ferry/qr-beam"],
              "systemd_unit": ["ferry-beam.service"],
              "rc_local": ["/opt/ferry/spark sync"],
              "shell_rc": ["nohup /opt/ferry/lift >/dev/null 2>&1 &"],
              "ld_preload": ["/lib/ferry/libbridge.so"],
              "at_job": ["f1e2d3c4b5a6"],
          }, indent=2) + "\n")


def build_mixb(root):
    """Trap: allowlisted hit must be honored; decoys must stay silent."""
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(root)
    os.makedirs(os.path.join(root, "etc", "cron.d"))
    # one allowlisted active-style entry + one decoy env/comment file
    write(os.path.join(root, "etc", "cron.d", "qbeam"),
          "*/11 * * * * root /opt/ferry/qr-beam\n")
    write(os.path.join(root, "etc", "cron.d", "policy"),
          "# rotated by fleet policy\nPATH=/usr/bin:/bin\n")

    os.makedirs(os.path.join(root, "var", "spool", "cron", "crontabs"))
    write(os.path.join(root, "var", "spool", "cron", "crontabs", "carrier"),
          "30 4 * * 2 /opt/ferry/barge\n")

    os.makedirs(os.path.join(root, "etc", "systemd", "system"))
    write(os.path.join(root, "etc", "systemd", "system", "mesh-gate.service"),
          "[Unit]\nDescription=Mesh gateway\n\n[Service]\n"
          "ExecStart=/opt/ferry/mesh-gate\n\n[Install]\n"
          "WantedBy=multi-user.target\n")

    write(os.path.join(root, "etc", "rc.local"),
          "#!/bin/sh\n"
          "# leave in place\n"
          "/opt/ferry/spark sync\n"
          "exit 0\n"
          "echo trap-decoy\n")

    os.makedirs(os.path.join(root, "etc", "profile.d"))
    write(os.path.join(root, "etc", "profile.d", "ferry-engage.sh"),
          "nohup /opt/ferry/lift >/dev/null 2>&1 &\n")

    write(os.path.join(root, "etc", "ld.so.preload"),
          "/lib/ferry/libbridge.so\n")

    os.makedirs(os.path.join(root, "var", "spool", "cron", "atjobs"))
    write(os.path.join(root, "var", "spool", "cron", "atjobs",
                       "a1b2c3d4e5f678"),
          "# V2\n/opt/ferry/digest\n")

    write(os.path.join(root, "etc", "persistence-allowlist.json"),
          json.dumps({
              "cron.d": ["/opt/ferry/qr-beam"],
              "systemd_unit": ["mesh-gate.service"],
              "rc_local": ["/opt/ferry/spark sync"],
              "shell_rc": ["nohup /opt/ferry/lift >/dev/null 2>&1 &"],
              "ld_preload": ["/lib/ferry/libbridge.so"],
              "at_job": ["a1b2c3d4e5f678"],
          }, indent=2) + "\n")


def build_mixc(root):
    """Empty readable tree: zero scanned locations with content."""
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(os.path.join(root, "etc", "cron.d"))
    os.makedirs(os.path.join(root, "var", "spool", "at"))
    os.makedirs(os.path.join(root, "run", "tmp"))


# ---------------------------------------------------------------------------
# Probe runner
# ---------------------------------------------------------------------------

def run_deliverable(root, out_path, expect_code=0):
    """Execute the deliverable CLI; return (returncode, bytes-write-ok)."""
    try:
        proc = subprocess.run(
            [sys.executable, SCANNER, root, out_path],
            capture_output=True, text=True, timeout=90)
    except Exception as exc:
        failures.append("deliverable on %r raised %s" % (root, exc))
        return None
    if proc.returncode != expect_code:
        failures.append("deliverable on %r exit=%s (wanted %s): %s" % (
            root, proc.returncode, expect_code,
            (proc.stderr or "").strip()[:200]))
        return None
    return proc.returncode


def check_case(root, label):
    """Run deliverable, recompute reference, compare parsed JSON exactly."""
    out_path = "/tmp/ashward_%s_out.json" % label
    if os.path.exists(out_path):
        os.remove(out_path)
    if run_deliverable(root, out_path, 0) is None:
        return
    try:
        with open(out_path, "r", encoding="utf-8") as fh:
            got = json.load(fh)
    except Exception as exc:
        failures.append("%s: deliverable report unparseable: %s" % (label, exc))
        return
    want = ReferenceAnalyzer(root).report()
    if got != want:
        failures.append("%s: report mismatch (got %d findings, want %d)"
                        % (label, len(got.get("findings", [])),
                           len(want["findings"])))
        got_rows = {(f["path"], f["line_or_key"], f["status"])
                    for f in got.get("findings", [])}
        want_rows = {(f["path"], f["line_or_key"], f["status"])
                     for f in want["findings"]}
        for row in sorted(want_rows - got_rows):
            failures.append("  %s: MISSING %r" % (label, row))
        for row in sorted(got_rows - want_rows):
            failures.append("  %s: EXTRA   %r" % (label, row))
    else:
        print("%s: OK (%d findings)" % (label, len(want["findings"])))


failures = []


def main():
    # --- 0. Deliverable presence -----------------------------------------
    if not os.path.isfile(SCANNER):
        failures.append("deliverable %s missing" % SCANNER)
        return 1

    # --- 1. Visible rootfs: fresh run, idempotency, deliverable report ----
    fresh = "/tmp/ashward_visible_run.json"
    if os.path.exists(fresh):
        os.remove(fresh)
    if run_deliverable(VISIBLE_ROOT, fresh, 0) is None:
        return 1
    try:
        with open(fresh, "rb") as fh:
            fresh_bytes = fh.read()
        with open(VISIBLE_REPORT, "rb") as fh:
            report_bytes = fh.read()
    except OSError as exc:
        failures.append("visible report unreadable: %s" % exc)
        return 1
    if fresh_bytes != report_bytes:
        failures.append(
            "/app/findings.json does not match a fresh scanner run on "
            "/app/rootfs (byte-identical expected: idempotency)")
    second = "/tmp/ashward_visible_run2.json"
    if os.path.exists(second):
        os.remove(second)
    if run_deliverable(VISIBLE_ROOT, second, 0) is None:
        return 1
    try:
        with open(second, "rb") as fh:
            second_bytes = fh.read()
    except OSError:
        failures.append("second visible run did not write a report")
        return 1
    if fresh_bytes != second_bytes:
        failures.append("visible run is not byte-idempotent across invocations")
    try:
        got = json.loads(fresh_bytes.decode("utf-8"))
    except Exception as exc:
        failures.append("visible report unparseable: %s" % exc)
        return 1
    want = ReferenceAnalyzer(VISIBLE_ROOT).report()
    if got != want:
        failures.append("visible report differs from reference recompute "
                        "(%d vs %d findings)"
                        % (len(got.get("findings", [])),
                           len(want["findings"])))
    else:
        print("visible: OK (%d findings, byte-idempotent)"
              % len(want["findings"]))

    # --- 2. Hidden trees ---------------------------------------------------
    hidden = [
        ("/tmp/ashward_mixa", build_mixa),
        ("/tmp/ashward_mixb", build_mixb),
        ("/tmp/ashward_mixc", build_mixc),
    ]
    for root, builder in hidden:
        builder(root)
        check_case(root, os.path.basename(root))

    # mixa runs twice for byte idempotency on a hidden tree
    out_a1 = "/tmp/ashward_mixa_one.json"
    out_a2 = "/tmp/ashward_mixa_two.json"
    for out in (out_a1, out_a2):
        if os.path.exists(out):
            os.remove(out)
    if run_deliverable("/tmp/ashward_mixa", out_a1, 0) is not None:
        if run_deliverable("/tmp/ashward_mixa", out_a2, 0) is not None:
            try:
                with open(out_a1, "rb") as fh:
                    b1 = fh.read()
                with open(out_a2, "rb") as fh:
                    b2 = fh.read()
                if b1 != b2:
                    failures.append("hidden mixa run is not byte-idempotent")
                else:
                    print("hidden idempotency: OK")
            except OSError as exc:
                failures.append("hidden idempotency read error: %s" % exc)

    # --- 3. Exit-code contract ---------------------------------------------
    nosuch = "/tmp/ashward_no_such_tree_9f2b1c"
    if run_deliverable(nosuch, "/tmp/ashward_nosuch_out.json", 2) is None:
        return 1
    print("exit-code contract: OK")

    if failures:
        print("verify failures:")
        for msg in failures:
            print("  - " + msg)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
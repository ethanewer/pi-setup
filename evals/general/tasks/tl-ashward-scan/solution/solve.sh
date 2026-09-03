#!/bin/bash
#
# tl-ashward-scan oracle. Authors the persistence-artifact scanner
# /app/scan_persistence.py from the documented contract, runs it on the
# visible tree /app/rootfs to produce /app/findings.json, and verifies the
# report round-trips (byte-stable across two runs). Never reads /tests.
set -euo pipefail

cat > /app/scan_persistence.py <<'PYEOF'
#!/usr/bin/env python3
"""Ashward workbench: idempotent Linux persistence-artifact scanner.

Scans ONLY the documented locations under the given rootfs tree and reports
structured findings. See the task contract for the exact rule set.
"""
import json
import os
import re
import sys

# ---- shared patterns (documented) ----
TIME_RE = re.compile(r'^[0-9A-Za-z*,/\-?]+$')
USER_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_-]*$')
CRON_ENV_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*\s*=')
SHELL_ENV_RE = re.compile(r'^(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=\s*\S*$')
AT_NAME_RE = re.compile(r'^[0-9a-fA-F]{6,}$')
UNIT_EXTS = ('.service', '.timer', '.socket', '.path', '.target',
             '.mount', '.automount', '.swap', '.slice')
SHELL_KEYWORDS = ('if', 'then', 'else', 'elif', 'fi', 'for', 'while',
                  'until', 'do', 'done', 'case', 'esac', 'in',
                  'select', 'function', 'time')

SYSTEMD_LOCATIONS = (
    'etc/systemd/system',
    'usr/lib/systemd/system',
    'lib/systemd/system',
    'run/systemd/units',
)


def is_comment(line):
    return line == '' or line[0] in '#;'


def read_lines(path):
    """Return [(1-based line number, line-without-trailing-CR, raw)]."""
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as fh:
            text = fh.read()
    except OSError:
        return []
    out = []
    for i, raw in enumerate(text.split('\n')):
        if raw.endswith('\r'):
            raw = raw[:-1]
        out.append((i + 1, raw.strip(), raw))
    return out


def load_allowlist(root):
    path = os.path.join(root, 'etc', 'persistence-allowlist.json')
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    return {k: set(v) for k, v in data.items() if isinstance(v, list)}


def emit(kind, path, key, status, evidence):
    return {
        'location_kind': kind,
        'path': path,
        'line_or_key': key,
        'status': status,
        'evidence': evidence,
    }


# ---------- cron family (cron.d + crontab) ----------
def scan_cron_file(path, kind, allow):
    found = []
    for lineno, line, raw in read_lines(path):
        if is_comment(line):
            continue
        if CRON_ENV_RE.match(line):
            continue
        tokens = line.split()
        if not tokens:
            continue
        if tokens[0].startswith('@'):
            rest = tokens[1:]
        elif len(tokens) >= 6 and all(TIME_RE.fullmatch(t) for t in tokens[:5]):
            rest = tokens[5:]
        else:
            continue
        if len(rest) >= 2 and USER_RE.fullmatch(rest[0]):
            command = ' '.join(rest[1:])
        else:
            command = ' '.join(rest)
        command = command.strip()
        if command == '':
            continue
        if command in allow.get(kind, ()):
            status, evidence = 'allowlisted', 'allowlisted entry'
        elif command.split()[0].startswith('#'):
            status, evidence = 'disabled', line
        else:
            status, evidence = 'active', line
        found.append(emit(kind, path, lineno, status, evidence))
    return found


def scan_cron_locations(root, allow):
    found = []

    d = os.path.join(root, 'etc', 'cron.d')
    try:
        with os.scandir(d) as it:
            for e in it:
                if e.is_file():
                    found.extend(scan_cron_file(e.path, 'cron.d', allow))
    except OSError:
        pass

    p = os.path.join(root, 'etc', 'crontab')
    if os.path.isfile(p):
        found.extend(scan_cron_file(p, 'crontab', allow))

    d = os.path.join(root, 'var', 'spool', 'cron', 'crontabs')
    try:
        with os.scandir(d) as it:
            for e in it:
                if e.is_file():
                    found.extend(scan_cron_file(e.path, 'crontab', allow))
    except OSError:
        pass

    return found


# ---------- systemd units ----------
def scan_systemd_locations(root, allow):
    found = []
    for sub in SYSTEMD_LOCATIONS:
        top = os.path.join(root, sub)
        for dirpath, _dirs, names in os.walk(top):
            for name in names:
                if not name.endswith(UNIT_EXTS):
                    continue
                full = os.path.join(dirpath, name)
                if os.path.islink(full):
                    continue
                in_install = False
                active = False
                for _lineno, line, _raw in read_lines(full):
                    if line.startswith('[') and line.endswith(']'):
                        in_install = line.lower() == '[install]'
                        continue
                    if not in_install or is_comment(line):
                        continue
                    head, sep, value = line.partition('=')
                    if sep and value.split('#', 1)[0].strip() \
                            and head.strip() in ('WantedBy', 'RequiredBy'):
                        active = True
                        break
                if name in allow.get('systemd_unit', ()):
                    status, evidence = 'allowlisted', 'allowlisted entry'
                elif active:
                    status, evidence = 'active', 'active via [Install]'
                else:
                    status, evidence = 'disabled', \
                        'disabled: no [Install] WantedBy/RequiredBy'
                found.append(emit('systemd_unit', full, name, status, evidence))
    return found


# ---------- rc.local ----------
def scan_rc_local(root, allow):
    found = []
    path = os.path.join(root, 'etc', 'rc.local')
    for lineno, line, raw in read_lines(path):
        if is_comment(line):
            continue
        if line.split()[0] == 'exit':
            break
        if line in allow.get('rc_local', ()):
            status, evidence = 'allowlisted', 'allowlisted entry'
        else:
            status, evidence = 'active', line
        found.append(emit('rc_local', path, lineno, status, evidence))
    return found


# ---------- shell rc ----------
def scan_shell_rc_file(path, allow):
    found = []
    for lineno, line, raw in read_lines(path):
        if is_comment(line):
            continue
        first = line.split()[0]
        if first in SHELL_KEYWORDS:
            continue
        if first[0] in '[!({':
            continue
        if SHELL_ENV_RE.match(line):
            continue
        if line in allow.get('shell_rc', ()):
            status, evidence = 'allowlisted', 'allowlisted entry'
        else:
            status, evidence = 'active', line
        found.append(emit('shell_rc', path, lineno, status, evidence))
    return found


def scan_shell_rc_locations(root, allow):
    found = []
    files = [
        os.path.join(root, 'etc', 'profile'),
        os.path.join(root, 'etc', 'bash.bashrc'),
    ]
    pd = os.path.join(root, 'etc', 'profile.d')
    try:
        with os.scandir(pd) as it:
            for e in it:
                if e.is_file() and e.name.endswith('.sh'):
                    files.append(e.path)
    except OSError:
        pass
    for base in ('.bashrc', '.profile'):
        p = os.path.join(root, 'root', base)
        if os.path.isfile(p):
            files.append(p)
    home = os.path.join(root, 'home')
    try:
        with os.scandir(home) as it:
            for e in it:
                if not e.is_dir():
                    continue
                for base in ('.bashrc', '.profile', '.bash_profile'):
                    p = os.path.join(e.path, base)
                    if os.path.isfile(p):
                        files.append(p)
    except OSError:
        pass
    for p in files:
        found.extend(scan_shell_rc_file(p, allow))
    return found


# ---------- ld.so.preload ----------
def scan_ld_preload(root, allow):
    found = []
    path = os.path.join(root, 'etc', 'ld.so.preload')
    for lineno, line, raw in read_lines(path):
        if is_comment(line):
            continue
        if line in allow.get('ld_preload', ()):
            status, evidence = 'allowlisted', 'allowlisted entry'
        else:
            status, evidence = 'active', line
        found.append(emit('ld_preload', path, lineno, status, evidence))
    return found


# ---------- at-job spools ----------
def scan_at_locations(root, allow):
    found = []
    for sub in ('var/spool/at', 'var/spool/cron/atjobs'):
        d = os.path.join(root, sub)
        try:
            with os.scandir(d) as it:
                for e in it:
                    if not e.is_file():
                        continue
                    if not AT_NAME_RE.fullmatch(e.name):
                        continue
                    if e.name in allow.get('at_job', ()):
                        status, evidence = 'allowlisted', 'allowlisted entry'
                    else:
                        status, evidence = 'active', 'at-job spool file'
                    found.append(emit('at_job', e.path, e.name,
                                      status, evidence))
        except OSError:
            pass
    return found


def scan(root):
    allow = load_allowlist(root)
    findings = []
    findings.extend(scan_cron_locations(root, allow))
    findings.extend(scan_systemd_locations(root, allow))
    findings.extend(scan_rc_local(root, allow))
    findings.extend(scan_shell_rc_locations(root, allow))
    findings.extend(scan_ld_preload(root, allow))
    findings.extend(scan_at_locations(root, allow))
    findings.sort(key=lambda f: (f['location_kind'], f['path'],
                                 str(f['line_or_key'])))
    return {'root': root, 'findings': findings}


def main(argv):
    if len(argv) != 3:
        print('usage: scan_persistence.py <rootfs_dir> <report.json>',
              file=sys.stderr)
        return 2
    root, report = argv[1], argv[2]
    if not os.path.isdir(root):
        return 2
    try:
        payload = json.dumps(scan(root), indent=2, sort_keys=True,
                             ensure_ascii=False)
        with open(report, 'w', encoding='utf-8') as fh:
            fh.write(payload + '\n')
    except OSError:
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
PYEOF
chmod 0755 /app/scan_persistence.py

python3 /app/scan_persistence.py /app/rootfs /app/findings.json
python3 /app/scan_persistence.py /app/rootfs /tmp/ashward_oracle_repeat.json
cmp -s /app/findings.json /tmp/ashward_oracle_repeat.json || {
  echo "oracle: scanner not byte-idempotent on /app/rootfs" >&2
  exit 1
}
rm -f /tmp/ashward_oracle_repeat.json

echo "solve.sh done: /app/scan_persistence.py + /app/findings.json written"
python3 -c "import json; d=json.load(open('/app/findings.json')); print('findings:', len(d['findings']))"

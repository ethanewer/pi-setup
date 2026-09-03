#!/bin/bash
# Oracle for tl-scroll-changelog: writes the changelogger CLI deliverable,
# runs it on the visible repository state, and confirms the visible release
# deliverables exist. Never reads /tests.
set -u

cat > /app/changelogger.py <<'PY'
#!/usr/bin/env python3
"""changelogger — per-package semver bumps + canonical CHANGELOG.md files
from a monorepo's conventional commits.

Usage:
    python3 /app/changelogger.py <repo_state_dir> --date YYYY-MM-DD --out <dir>

Reads  <repo_state_dir>/commits.jsonl, packages.json, last_tag.json
Writes <out>/bumps.json and <out>/<name>/CHANGELOG.md
Exit 0 on success; 1 on any input/output error (message on stderr).
"""
import argparse
import json
import re
import sys
from pathlib import Path

HEADER_A = re.compile(r"^([a-z]+)(?:\(([a-z0-9_-]+)\))?(!?):\s+(.+)$")
HEADER_B = re.compile(r"^([a-z]+)!\(([a-z0-9_-]+)\):\s+(.+)$")

KNOWN_TYPES = {
    "feat", "fix", "docs", "chore", "refactor", "perf",
    "test", "style", "build", "ci", "revert",
}
ENTRY_SECTION = {
    "feat": "Added",
    "fix": "Fixed",
    "refactor": "Changed", "perf": "Changed", "test": "Changed",
    "style": "Changed", "build": "Changed", "ci": "Changed",
    "revert": "Changed",
}
CLASS_OF = {
    "feat": "minor",
    "fix": "patch", "refactor": "patch", "perf": "patch", "test": "patch",
    "style": "patch", "build": "patch", "ci": "patch", "revert": "patch",
    "docs": "none", "chore": "none",
}
PRIORITY = {"none": 0, "patch": 1, "minor": 2, "major": 3}


def parse_commit_line(raw):
    try:
        obj = json.loads(raw)
    except Exception:
        return None
    if not isinstance(obj, dict):
        return None
    h = obj.get("hash")
    msg = obj.get("message")
    files = obj.get("files")
    if not isinstance(h, str) or not isinstance(msg, str) or not isinstance(files, list):
        return None
    return h, msg, [f for f in files if isinstance(f, str)]


def split_header(message):
    lines = message.splitlines()
    if not lines:
        return None
    m = HEADER_A.match(lines[0])
    if m:
        ctype, scope, bang, desc = m.groups()
    else:
        m = HEADER_B.match(lines[0])
        if not m:
            return None
        ctype, scope, desc = m.groups()
        bang = "!"
    if ctype not in KNOWN_TYPES:
        return None
    breaking = bang == "!" or any(
        ln.strip().startswith("BREAKING CHANGE:") for ln in lines[1:]
    )
    return ctype, scope, breaking, desc.strip()


def load_state(state_dir):
    state_dir = Path(state_dir)
    packages_raw = json.loads((state_dir / "packages.json").read_text())
    if not isinstance(packages_raw, dict):
        raise ValueError("packages.json must be an object")
    packages = {}
    for name, info in packages_raw.items():
        if not isinstance(info, dict) or "path" not in info or "version" not in info:
            raise ValueError("bad package entry: %r" % name)
        packages[name] = (str(info["path"]), str(info["version"]))
    tag_raw = json.loads((state_dir / "last_tag.json").read_text())
    if not isinstance(tag_raw, dict) or not isinstance(tag_raw.get("tag"), str):
        raise ValueError("last_tag.json must be an object with a string 'tag'")
    tag = tag_raw["tag"]
    commits = []
    for line in (state_dir / "commits.jsonl").read_text().splitlines():
        pc = parse_commit_line(line)
        if pc is not None:
            commits.append(pc)
    return packages, tag, commits


def next_version(version, cls):
    parts = version.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError("bad version: %r" % version)
    major, minor, patch = (int(p) for p in parts)
    if cls == "major":
        return "%d.0.0" % (major + 1)
    if cls == "minor":
        return "%d.%d.0" % (major, minor + 1)
    if cls == "patch":
        return "%d.%d.%d" % (major, minor, patch + 1)
    raise ValueError("bad bump class: %r" % cls)


def assign_commits(commits, packages):
    out = {name: [] for name in packages}
    for h, msg, files in commits:
        parsed = split_header(msg)
        if parsed is None:
            continue
        ctype, scope, breaking, desc = parsed
        cls = "major" if breaking else CLASS_OF[ctype]
        if scope is not None:
            if scope not in packages:
                continue
            targets = [scope]
        else:
            targets = []
            for f in files:
                best, best_len = None, -1
                for name, (prefix, _ver) in packages.items():
                    if f.startswith(prefix) and len(prefix) > best_len:
                        best, best_len = name, len(prefix)
                if best is not None and best not in targets:
                    targets.append(best)
            if not targets:
                continue
        section = ENTRY_SECTION.get(ctype)
        for name in targets:
            out[name].append((h, desc, section, cls))
    return out


def render_changelog(name, entries, to_version, date, tag):
    lines = ["# %s Changelog" % name, "", "## [%s] - %s" % (to_version, date), "",
             "Previous release: %s" % tag]
    for section in ("Added", "Fixed", "Changed"):
        rows = [(h, d) for (h, d, s, _c) in entries if s == section]
        if not rows:
            continue
        lines += ["", "### %s" % section]
        for h, d in rows:
            lines.append("- %s (%s)" % (d, h[:7]))
    return "\n".join(lines) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(prog="changelogger")
    ap.add_argument("repo_state_dir")
    ap.add_argument("--date", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.date):
        print("changelogger: bad --date %r (need YYYY-MM-DD)" % args.date, file=sys.stderr)
        return 1
    try:
        packages, tag, commits = load_state(args.repo_state_dir)
        assigned = assign_commits(commits, packages)

        bumps = {}
        changelogs = {}
        for name in sorted(packages):
            entries = assigned[name]
            if not entries:
                continue
            best = "none"
            for (_h, _d, _s, cls) in entries:
                if PRIORITY[cls] > PRIORITY[best]:
                    best = cls
            if best == "none":
                continue
            from_ver = packages[name][1]
            to_ver = next_version(from_ver, best)
            bumps[name] = {"from": from_ver, "to": to_ver, "bump": best}
            changelogs[name] = render_changelog(name, entries, to_ver, args.date, tag)

        out_dir = Path(args.out)
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "bumps.json").write_text(
            json.dumps(bumps, indent=2) + "\n")
        for name, text in changelogs.items():
            pkg_dir = out_dir / name
            pkg_dir.mkdir(parents=True, exist_ok=True)
            (pkg_dir / "CHANGELOG.md").write_text(text)
        return 0
    except Exception as exc:
        print("changelogger: error: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY

# Produce the visible release deliverables.
python3 /app/changelogger.py /app/repo_state --date 2025-06-15 --out /app/release
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "oracle: changelogger visible run failed (exit $rc)" >&2
  exit 1
fi

# Confirm every deliverable file was created.
for f in /app/release/bumps.json \
         /app/release/core/CHANGELOG.md \
         /app/release/app/CHANGELOG.md \
         /app/release/tools/CHANGELOG.md; do
  if [ ! -f "$f" ]; then
    echo "oracle: missing deliverable $f" >&2
    exit 1
  fi
done

echo "solve.sh done"
ls -R /app/release
#!/usr/bin/env python3
"""seabolt release pipeline (reference implementation).

A reusable, general release CLI for git repositories that use conventional
commit messages.  Given a working tree it:

  1. derives the next semver release from the conventional commits since the
     last release tag (or from the whole history when no release tag exists),
  2. writes a changelog grouped by change type with breaking changes called
     out,
  3. builds the reproducible source artifact of the HEAD tree and records its
     byte hash in a provenance file,
  4. creates an annotated release tag at HEAD.

Usage:
    python3 release.py <REPO_DIR> <OUT_DIR>

Exit codes: 0 success; 3 nothing to release (no conventional commits since the
base release tag); non-zero on error.

The rules implemented here are the exact contract described in
instruction.md; the grader rebuilds the artifact from the same repository and
compares byte hashes, so the artifact pipeline must be used verbatim:

    git -C <REPO> archive --format=tar HEAD | gzip -n > <OUT>/release-<ver>.tar.gz
"""

import hashlib
import os
import re
import subprocess
import sys

CONV = re.compile(r"^([a-z]+)(?:\(([^()]*)\))?(!)?: (.*)$")
BREAK_LINE = re.compile(r"^\s*breaking[ -]change:", re.IGNORECASE)
REL_TAG = re.compile(r"v(\d+)\.(\d+)\.(\d+)")
SECTION_ORDER = ("Breaking Changes", "Added", "Fixed", "Changed")


class ReleaseError(RuntimeError):
    pass


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def parse_commit(message):
    """Parse one commit message into (type, breaking, subject) or None when
    the commit is not conventional."""
    parts = message.split("\n", 1)
    subject = parts[0]
    rest = parts[1] if len(parts) > 1 else ""
    m = CONV.match(subject)
    if not m:
        return None
    typ, bang, subj = m.group(1), m.group(3), m.group(4).rstrip()
    breaking = bool(bang) or any(
        BREAK_LINE.match(line) for line in rest.split("\n"))
    return typ, breaking, subj


def derive(repo):
    """Return (version, changelog_text, date, head_sha) or None when there is
    nothing to release."""
    releases = []
    for t in git(repo, "tag").splitlines():
        m = REL_TAG.fullmatch(t.strip())
        if m:
            releases.append((tuple(int(g) for g in m.groups()), t.strip()))
    base = max(releases)[0] if releases else (0, 0, 0)
    base_tag = None if not releases else max(releases)[1]

    fmt = "%x1e%H%x1f%ct%x1f%B"
    if base_tag:
        raw = git(repo, "log", "--format=" + fmt, f"{base_tag}..HEAD")
    else:
        raw = git(repo, "log", "--format=" + fmt, "HEAD")
    date = git(repo, "log", "-1", "--format=%cd", "--date=short", "HEAD").strip()
    head = git(repo, "rev-parse", "HEAD").strip()

    commits = []
    for rec in raw.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        sha, ts, msg = rec.split("\x1f", 2)
        commits.append({"sha": sha, "ct": int(ts), "msg": msg})

    counted = []
    for c in commits:
        parsed = parse_commit(c["msg"])
        if parsed is None:
            continue
        typ, breaking, subj = parsed
        counted.append({"sha": c["sha"], "ct": c["ct"], "subj": subj,
                        "type": typ, "breaking": breaking})

    if not counted:
        return None

    if any(c["breaking"] for c in counted):
        nv = (base[0] + 1, 0, 0)
    elif any(c["type"] == "feat" for c in counted):
        nv = (base[0], base[1] + 1, 0)
    else:
        nv = (base[0], base[1], base[2] + 1)
    version = ".".join(str(x) for x in nv)

    groups = {name: [] for name in SECTION_ORDER}
    for c in counted:
        if c["breaking"]:
            g = "Breaking Changes"
        elif c["type"] == "feat":
            g = "Added"
        elif c["type"] == "fix":
            g = "Fixed"
        else:
            g = "Changed"
        groups[g].append(c)
    for g in groups:
        groups[g].sort(key=lambda c: (-c["ct"], c["sha"]))

    lines = ["# Changelog", "", f"## [{version}] - {date}", ""]
    first = True
    for name in SECTION_ORDER:
        if not groups[name]:
            continue
        if not first:
            lines.append("")
        lines.append(f"### {name}")
        lines.append("")
        for c in groups[name]:
            lines.append(f"- {c['subj']} ({c['sha']})")
        first = False
    changelog = "\n".join(lines) + "\n"
    return version, changelog, date, head


def build_artifact(repo, out_path):
    """Compress the HEAD tree exactly like the verifier's rebuild does."""
    with open(out_path, "wb") as fh:
        archive = subprocess.Popen(
            ["git", "-C", repo, "archive", "--format=tar", "HEAD"],
            stdout=subprocess.PIPE)
        gz = subprocess.Popen(["gzip", "-n"], stdin=archive.stdout, stdout=fh)
        archive.stdout.close()
        rc1 = archive.wait()
        rc2 = gz.wait()
    if rc1 != 0 or rc2 != 0:
        raise ReleaseError("artifact build failed")


def main(argv):
    if len(argv) != 3:
        print("usage: release.py <REPO_DIR> <OUT_DIR>", file=sys.stderr)
        return 2
    repo, out_dir = argv[1], argv[2]

    derived = derive(repo)
    if derived is None:
        print("no releasable commits", file=sys.stderr)
        return 3
    version, changelog, _date, head = derived

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "CHANGELOG.md"), "w") as fh:
        fh.write(changelog)
    with open(os.path.join(out_dir, "version.txt"), "w") as fh:
        fh.write(version + "\n")

    artifact = os.path.join(out_dir, f"release-{version}.tar.gz")
    build_artifact(repo, artifact)
    with open(artifact, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()

    provenance = "\n".join([
        f"version: {version}",
        f"commit: {head}",
        f"tag: v{version}",
        f"artifact: release-{version}.tar.gz",
        f"artifact_sha256: {digest}",
    ]) + "\n"
    with open(os.path.join(out_dir, "provenance.txt"), "w") as fh:
        fh.write(provenance)

    tag = f"v{version}"
    r = subprocess.run(
        ["git", "-C", repo, "tag", "-a", tag, "-m", f"Release {version}"],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise ReleaseError(f"tag creation failed: {r.stderr.strip()}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except ReleaseError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
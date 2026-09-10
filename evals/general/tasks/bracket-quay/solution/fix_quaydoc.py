#!/usr/bin/env python3
"""The real repair for the quaydoc anchor regression.

Applies the canonical fix to quaydoc/toc.py, verifies it with the shipped
suite and an ad-hoc docset using the trigger headings from the bug report,
identifies the introducing commit via git's pickaxe (the marker string only
ever existed in the regression), and writes /app/postmortem.md naming it.

This is the oracle's solver: it does the work, never reads /tests, and
never hardcodes a commit hash — the hash is derived from the repository's
own history.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path("/app/quayside")
MARKER = 'text = text.replace("&", "and")'

BUGGY_BLOCK = '''        text = str(title)
        text = text.replace("&", "and")
        text = text.replace(":", "")
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        slug = re.sub(r"-{2,}", "-", slug)
        return slug or "section"
'''
FIXED_BLOCK = '''        text = str(title)
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        slug = re.sub(r"-{2,}", "-", slug)
        return slug or "section"
'''


def run(*args, cwd=str(REPO)):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd)


def apply_fix():
    """Remove the two special-cased replacements from AnchorMap.anchor_for.

    The heading ids must agree with the fragments produced by
    quaydoc.links.target_for / quaydoc.slugs.anchor_of; the regression
    introduced a locally-divergent spelling (ampersand -> 'and', colons
    dropped) that no longer matches the shared slugifier.
    """
    toc = REPO / "quaydoc/toc.py"
    text = toc.read_text(encoding="utf-8")
    if text.count(BUGGY_BLOCK) != 1:
        raise SystemExit(
            f"expected the regressed anchor_for body once, found "
            f"{text.count(BUGGY_BLOCK)}")
    toc.write_text(text.replace(BUGGY_BLOCK, FIXED_BLOCK), encoding="utf-8")
    print("fixed quaydoc/toc.py (anchor computation back to canonical)")


def find_introducing_commit():
    """Return (sha, subject) of the commit that introduced the regression."""
    log = run("git", "log", "--reverse", "-S", MARKER, "--format=%H",
              "--", "quaydoc/toc.py")
    matches = [line for line in log.stdout.splitlines() if line.strip()]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one introducing commit, got "
                         f"{len(matches)}")
    sha = matches[0]
    subject = run("git", "log", "-1", "--format=%s", sha).stdout.strip()
    return sha, subject


def verify():
    """Run the shipped suite and a trigger-heading build; both must pass."""
    pytest = run(sys.executable, "-m", "pytest", "-q", "tests")
    if pytest.returncode != 0:
        raise SystemExit("shipped pytest suite is not green after the fix:\n"
                         + pytest.stdout[-800:])

    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "docs")
        os.makedirs(root)
        titles = ["Setup & First Steps", "FAQ: v2"]
        with open(os.path.join(root, "index.qd"), "w",
                  encoding="utf-8") as fh:
            fh.write("---\ntitle: Home\n---\n\n" +
                     "\n".join(f"- [[{t}]]" for t in titles) + "\n")
        with open(os.path.join(root, "guide.qd"), "w",
                  encoding="utf-8") as fh:
            fh.write("---\ntitle: Guide\n---\n\n" +
                     "\n".join(f"## {t}" for t in titles) + "\n")
        outdir = os.path.join(tmp, "site")
        build = run(sys.executable, "-m", "quaydoc.cli", "build", root,
                    "-o", outdir)
        check = run(sys.executable, "-m", "quaydoc.cli", "check", outdir)
        if build.returncode != 0 or check.returncode != 0:
            raise SystemExit("trigger-heading build/check failed:\n"
                             + build.stderr + check.stdout)
    print("verified: shipped suite green, trigger-heading build+check clean")


def write_postmortem(sha, subject):
    body = (
        "# Postmortem: broken fragment links for symbol-heavy headings\n"
        "\n"
        "## Regression\n"
        "\n"
        f"Introduced by commit {sha}\n"
        "\n"
        "## Commit subject\n"
        "\n"
        f"`{subject}`\n"
        "\n"
        "## Root cause\n"
        "\n"
        "Heading ids and fragment links are produced on two sides of the\n"
        "render pipeline. The table of contents assigns every heading its\n"
        "`id` attribute; the reference machinery computes the `#fragment`\n"
        "for a `[[...]]` link. The two sides are documented as needing to\n"
        "produce identical output (both wrap the shared slugifier in\n"
        "`quaydoc.slugs`), and that is what makes every fragment resolvable.\n"
        "\n"
        "The regression relaxed the id side: heading ids special-cased\n"
        "ampersands (transliterating them to 'and') and dropped colons.\n"
        "Any heading whose title contained one of those characters then\n"
        "rendered with an id that none of its links pointed at, so TOC\n"
        "jump-links and `[[...]]` references to such sections broke, and\n"
        "`quaydoc check` reported `broken-fragment` for the published site.\n"
        "Per-module tests stayed green because no individual module's unit\n"
        "tests feed the id side those characters; the failure only shows\n"
        "up when a page is rendered and the two halves meet.\n"
        "\n"
        "## Fix\n"
        "\n"
        "Restored the shared slugifier semantics on the id side (removed\n"
        "the special-cased replacements), so heading ids and link\n"
        "fragments agree again. Verified by rebuilding the reproduction\n"
        "docset and running `quaydoc check`, plus the full shipped test\n"
        "suite.\n"
        "\n"
        "## Diagnosis route\n"
        "\n"
        "1. Reproduced with a docset containing headings with '&' and ':'\n"
        "   (build + `quaydoc check` reported broken fragments).\n"
        "2. Traced the two anchor computations (id side vs fragment side)\n"
        "   and found they had drifted.\n"
        "3. With `git log -S`/`git blame` on the diverging code, pinned the\n"
        "   commit above as the one that introduced the divergence.\n"
    )
    Path("/app/postmortem.md").write_text(body, encoding="utf-8")
    print(f"wrote /app/postmortem.md naming {sha}")


def main():
    if not (REPO / ".git").is_dir():
        raise SystemExit(f"{REPO} is not a git repository")
    status = run("git", "status", "--porcelain")
    if status.returncode != 0:
        raise SystemExit("cannot read git status")
    apply_fix()
    sha, subject = find_introducing_commit()
    verify()
    write_postmortem(sha, subject)
    print(f"introducing commit: {sha} {subject!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
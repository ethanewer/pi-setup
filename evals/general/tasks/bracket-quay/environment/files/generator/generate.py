#!/usr/bin/env python3
"""Fixture generator for the bracket-quay task.

Builds /app/quayside — the quaydoc monorepo — from the corpus, replaying a
real 31-commit git history with fixed dates:

* each commit copies the named files from the corpus (final state) or from
  the ``history/`` variants (earlier states of files that evolved),
* commit 28, "feat: friendlier anchor ids for punctuation-heavy titles",
  rewrites ``quaydoc/toc.py`` from the shared-slug delegation to a custom
  inline variant — THAT is the regression the task is about, reachable only
  through the toc/links anchor interaction,
* the working tree is left in the final (regressed) state.

Everything is deterministic: fixed commit dates, fixed identity, same file
bytes, so the same image builds the same history every time.  The generator
itself is fixture tooling, not part of the delivered repository.
"""

from __future__ import annotations

import datetime
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path("/app/quayside")
CORPUS = Path("/app/generator/corpus")
HISTORY = Path("/app/generator/history")

BASE_TS = datetime.datetime(2025, 1, 15, 9, 0, 0, tzinfo=datetime.timezone.utc)
STEP = datetime.timedelta(days=2)

# (subject, [(rel_path, source), ...])  source: "c"=corpus or history filename
COMMITS = [
    ("chore: scaffold package metadata and initial docs skeleton",
     [("pyproject.toml", "pyproject.toml.v1"),
      ("README.md", "README.md.v1"),
      ("LICENSE", "c"), (".gitignore", "c")]),
    ("feat: exception hierarchy and shared filesystem helpers",
     [("quaydoc/errors.py", "c"), ("quaydoc/util.py", "c")]),
    ("feat: source token model",
     [("quaydoc/tokens.py", "c")]),
    ("feat: admonition directives",
     [("quaydoc/directives.py", "c")]),
    ("feat: line-oriented block lexer",
     [("quaydoc/lexer.py", "c")]),
    ("feat: document node types and parser",
     [("quaydoc/nodes.py", "c"), ("quaydoc/parser.py", "c")]),
    ("feat: inline markup parser",
     [("quaydoc/inline.py", "c")]),
    ("feat: canonical slug and anchor utility",
     [("quaydoc/slugs.py", "c")]),
    ("feat: link resolution and fragment targets",
     [("quaydoc/links.py", "c")]),
    ("feat: table of contents, section tree and anchor map",
     [("quaydoc/toc.py", "toc.py.v1")]),
    ("feat: block-to-HTML renderers",
     [("quaydoc/blocks.py", "c")]),
    ("feat: page shell rendering and postprocessing",
     [("quaydoc/html.py", "c")]),
    ("feat: template engine",
     [("quaydoc/template.py", "c")]),
    ("feat: default theme assets and sidebar template",
     [("quaydoc/theme.py", "c")]),
    ("feat: page model with front matter",
     [("quaydoc/page.py", "c")]),
    ("feat: site builder, config, discovery and navigation",
     [("quaydoc/site.py", "c"), ("quaydoc/config.py", "c"),
      ("quaydoc/finder.py", "c"), ("quaydoc/urls.py", "c"),
      ("quaydoc/nav.py", "c"), ("quaydoc/stats.py", "c")]),
    ("feat: CLI with build/serve/watch commands",
     [("quaydoc/cli.py", "c"), ("quaydoc/server.py", "c"),
      ("quaydoc/watch.py", "c"), ("quaydoc/printutil.py", "c"),
      ("quaydoc/__main__.py", "c"), ("quaydoc/redirects.py", "c")]),
    ("feat: search index, sitemap and atom feed",
     [("quaydoc/search.py", "c"), ("quaydoc/markup.py", "c"),
      ("quaydoc/sitemap.py", "c"), ("quaydoc/rss.py", "c")]),
    ("feat: link-integrity checker",
     [("quaydoc/check.py", "c")]),
    ("feat: syntax highlighting and text input helpers",
     [("quaydoc/highlight.py", "c"), ("quaydoc/textio.py", "c"),
      ("quaydoc/meta.py", "c")]),
    ("feat: source linter",
     [("quaydoc/lint.py", "c")]),
    ("feat: snippet rendering, migration tooling and build cache",
     [("quaydoc/snippet.py", "c"), ("quaydoc/migration.py", "c")]),
    ("test: lexer, parser and inline coverage",
     [("tests/conftest.py", "c"), ("tests/test_lexer.py", "c"),
      ("tests/test_parser.py", "c"), ("tests/test_inline.py", "c")]),
    ("test: slug, link and toc coverage",
     [("tests/test_slugs.py", "c"), ("tests/test_links.py", "c"),
      ("tests/test_toc.py", "c")]),
    ("test: renderer and template coverage",
     [("tests/test_blocks.py", "c"), ("tests/test_html.py", "c"),
      ("tests/test_template.py", "c")]),
    ("test: config, discovery and site-build coverage",
     [("tests/test_config.py", "c"), ("tests/test_finder.py", "c"),
      ("tests/test_site.py", "c")]),
    ("test: checker and CLI coverage",
     [("tests/test_check.py", "c"), ("tests/test_cli.py", "c"),
      ("tests/test_misc.py", "c")]),
    ("feat: friendlier anchor ids for titles with punctuation",
     [("quaydoc/toc.py", "c")]),
    ("docs: example documentation sites",
     [("examples/quaydoc.toml", "c"), ("examples/index.qd", "c"),
      ("examples/guide/building.qd", "c"),
      ("examples/guide/installation.qd", "c"),
      ("examples/guide/links.qd", "c"), ("examples/guide/writing.qd", "c"),
      ("examples/reference/cli.qd", "c"),
      ("examples/reference/config.qd", "c"),
      ("examples/topics/search.qd", "c"),
      ("examples/topics/theming.qd", "c"),
      ("examples/topics/troubleshooting.qd", "c"),
      ("docs/quaydoc.toml", "c"), ("docs/index.qd", "c"),
      ("docs/guide/building.qd", "c"), ("docs/guide/cheatsheet.qd", "c"),
      ("docs/guide/installation.qd", "c"), ("docs/guide/links.qd", "c"),
      ("docs/guide/writing.qd", "c"), ("docs/reference/api.qd", "c"),
      ("docs/reference/cli.qd", "c"), ("docs/reference/config.qd", "c"),
      ("docs/topics/contributing.qd", "c"), ("docs/topics/search.qd", "c"),
      ("docs/topics/theming.qd", "c"),
      ("docs/topics/troubleshooting.qd", "c")]),
    ("docs: user guide, changelog and release notes",
     [("README.md", "c"), ("CHANGELOG.md", "c")]),
    ("chore: release 0.9.0",
     [("quaydoc/__init__.py", "c"), ("pyproject.toml", "c")]),
]

# sanity: the regression markers must exist exactly where we expect them
TOC_FINAL = (CORPUS / "quaydoc/toc.py").read_text()
TOC_V1 = (HISTORY / "toc.py.v1").read_text()
MARKER = 'text = text.replace("&", "and")'
assert TOC_FINAL.count(MARKER) == 1, "regression marker must be in final toc.py"
assert MARKER not in TOC_V1, "pre-regression toc.py must be canonical"


def run(args, **kw):
    return subprocess.run(args, check=True, capture_output=True, **kw)


def git(*args):
    return run(["git", "-C", str(REPO)] + list(args))


def main() -> int:
    if REPO.exists():
        shutil.rmtree(REPO)
    REPO.mkdir(parents=True)

    git("init", "-q", "-b", "main")
    git("config", "user.email", "build@quayside.local")
    git("config", "user.name", "quayside build")
    git("config", "commit.gpgsign", "false")
    git("config", "core.autocrlf", "false")

    for index, (subject, files) in enumerate(COMMITS):
        ts = BASE_TS + index * STEP
        env = dict(os.environ)
        env["GIT_AUTHOR_DATE"] = ts.strftime("%Y-%m-%dT%H:%M:%S%z")
        env["GIT_COMMITTER_DATE"] = ts.strftime("%Y-%m-%dT%H:%M:%S%z")
        staged = []
        for rel, source in files:
            src = CORPUS / rel if source == "c" else HISTORY / source
            dest = REPO / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
            staged.append(rel)
        git("add", "-A")
        run(["git", "-C", str(REPO), "commit", "-q",
             "-m", subject, "-m", ""], env=env)

    # ---- post conditions -------------------------------------------------
    commit_count = int(git("rev-list", "--count", "HEAD").stdout.strip())
    if commit_count < 30:
        print(f"FATAL: only {commit_count} commits", file=sys.stderr)
        return 1

    marker_commit = git("log", "--reverse", "-S", MARKER, "--format=%H",
                        "--", "quaydoc/toc.py")
    lines = marker_commit.stdout.decode().splitlines()
    if len(lines) != 1:
        print(f"FATAL: expected exactly one introducing commit, "
              f"found {len(lines)}", file=sys.stderr)
        return 1
    subject = git("log", "-1", "--format=%s", lines[0]).stdout.decode().strip()
    if "friendlier anchor" not in subject:
        print(f"FATAL: unexpected introducing commit subject {subject!r}",
              file=sys.stderr)
        return 1

    py_files = [p for p in (REPO / "quaydoc").rglob("*.py")]
    pkg_loc = sum(len(p.read_text(errors="replace").splitlines())
                  for p in py_files)
    print(f"generated {REPO} with {commit_count} commits, "
          f"{len(py_files)} package modules, {pkg_loc} line(s) of package "
          f"source; regression commit: {lines[0][:12]} ({subject})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
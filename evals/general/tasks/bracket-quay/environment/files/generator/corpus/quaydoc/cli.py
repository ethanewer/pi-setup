"""Command-line interface.

Subcommands::

    quaydoc build  [ROOT] [-o OUT] [--archive PATH]
    quaydoc check  [OUTDIR]
    quaydoc serve  [OUTDIR] [--port N] [--host H]
    quaydoc watch  [ROOT]
    quaydoc search TERMS... [OUTDIR]
    quaydoc init   [ROOT]
    quaydoc --version
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from quaydoc import __version__
from quaydoc import printutil
from quaydoc.check import Checker
from quaydoc.config import load_config
from quaydoc.errors import QuaydocError
from quaydoc.search import query as search_query
from quaydoc.site import Site
from quaydoc.util import ensure_dir, read_text, write_text


def _parser():
    parser = argparse.ArgumentParser(
        prog="quaydoc",
        description="A self-contained documentation site generator.")
    parser.add_argument("--version", action="version",
                        version=f"quaydoc {__version__}")
    sub = parser.add_subparsers(dest="command", metavar="COMMAND")

    p_build = sub.add_parser("build", help="render a documentation tree")
    p_build.add_argument("root", nargs="?", default=".", help="docs root")
    p_build.add_argument("-o", "--output", help="output directory")
    p_build.add_argument("--archive", metavar="PATH",
                         help="bundle the output into a .tar.gz")
    p_build.add_argument("--config", help="path to quaydoc.toml")

    p_check = sub.add_parser("check", help="check a built site's links")
    p_check.add_argument("outdir", nargs="?", default=None,
                         help="build directory (default: ./site)")
    p_check.add_argument("--strict", action="store_true",
                         help="treat warnings as errors")
    p_check.add_argument("--ignore", nargs="*", default=(),
                         help="issue codes to ignore")

    p_serve = sub.add_parser("serve", help="serve a built site")
    p_serve.add_argument("outdir", nargs="?", default="site")
    p_serve.add_argument("--port", type=int, default=8000)
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--watch", action="store_true",
                         help="rebuild the site when sources change")

    p_watch = sub.add_parser("watch", help="rebuild on changes")
    p_watch.add_argument("root", nargs="?", default=".")

    p_search = sub.add_parser("search", help="query a built search index")
    p_search.add_argument("terms", nargs="+", help="search words")
    p_search.add_argument("outdir", nargs="?", default="site")
    p_search.add_argument("--json", action="store_true",
                          help="emit machine-readable output")

    p_init = sub.add_parser("init", help="scaffold a documentation tree")
    p_init.add_argument("root", nargs="?", default=".")

    p_lint = sub.add_parser("lint", help="lint documentation sources")
    p_lint.add_argument("root", nargs="?", default=".")

    p_quality = sub.add_parser("quality", help="documentation quality checks")
    p_quality.add_argument("root", nargs="?", default=".")

    p_anchors = sub.add_parser("anchors", help="print the heading inventory")
    p_anchors.add_argument("root", nargs="?", default=".")

    p_versions = sub.add_parser("versions", help="list version trees")
    p_versions.add_argument("root", nargs="?", default=".")

    p_migrate = sub.add_parser("migrate", help="migrate 0.8-era configs")
    p_migrate.add_argument("root", nargs="?", default=".")
    p_migrate.add_argument("--dry-run", action="store_true")

    p_list = sub.add_parser("list", help="list the pages of a tree")
    p_list.add_argument("root", nargs="?", default=".")
    p_list.add_argument("--columns", default="url,title,order,tags")

    p_stats = sub.add_parser("stats", help="source statistics for a tree")
    p_stats.add_argument("root", nargs="?", default=".")

    return parser


def cmd_build(args):
    config = load_config(args.root, path=args.config) if args.config else \
        load_config(args.root)
    site = Site(args.root, config).load()
    out = args.output or config.output_path
    stats = site.build(outdir=out, archive=args.archive)
    printutil.ok(stats.report())
    for warning in config.warnings + _page_warnings(site):
        printutil.warn(warning)
    return 0


def _page_warnings(site):
    out = []
    for page in site.pages:
        out.extend(page.warnings)
    return out


def cmd_check(args):
    out = args.outdir
    if out is None:
        out = os.path.join(os.getcwd(), "site")
    checker = Checker(out)
    issues = checker.all_issues()
    if args.ignore:
        ignored = set(args.ignore)
        issues = [i for i in issues if i.code not in ignored]
    strict = bool(getattr(args, "strict", False))
    errors = checker.write_report(issues,
                                  os.path.join(out, ".quay-check.txt"))
    total = len(issues)
    warnings = total - errors if not strict else 0
    if strict:
        errors = total
    for issue in issues:
        print(issue.render())
    print("")
    print(f"{len([i for i in issues if i.severity == 'error'])} error(s), "
          f"{len([i for i in issues if i.severity != 'error'])} warning(s)")
    return 0 if errors == 0 else 1


def cmd_serve(args):
    from quaydoc.server import serve
    if args.watch:
        import threading
        from quaydoc.watch import Watcher
        root = "."
        config = load_config(root)
        stop = threading.Event()

        def rebuild(changed):
            try:
                site = Site(root, load_config(root)).load()
                site.build(outdir=config.output_path)
                printutil.ok(f"rebuilt {len(changed)} change(s): "
                             + ", ".join(changed[:3]))
            except QuaydocError as exc:
                printutil.warn(f"rebuild failed: {exc}")

        thread = threading.Thread(
            target=lambda: Watcher(root, config).run(
                lambda c: rebuild(c) if not stop.is_set() else None),
            daemon=True)
        thread.start()
        try:
            serve(args.outdir, host=args.host, port=args.port)
        finally:
            stop.set()
        return 0
    serve(args.outdir, host=args.host, port=args.port)
    return 0


def cmd_watch(args):
    from quaydoc.watch import Watcher
    config = load_config(args.root)
    site = Site(args.root, config)
    site.load()

    def rebuild(changed):
        config = load_config(args.root)
        site.load()
        site.build(outdir=config.output_path)

    watcher = Watcher(args.root, config)
    watcher.run(rebuild)
    return 0


def cmd_search(args):
    index_path = os.path.join(args.outdir, "search_index.json")
    if not os.path.isfile(index_path):
        printutil.fail(f"{index_path}: no search index (build the site first)")
        return 1
    entries = json.loads(read_text(index_path))
    hits = search_query(entries, args.terms)
    if args.json:
        print(json.dumps(hits, ensure_ascii=False, indent=2))
        return 0
    if not hits:
        printutil.info("no matches")
        return 0
    for entry in hits:
        print(f"{entry['url']}  {entry['title']}")
    return 0


def cmd_lint(args):
    from quaydoc.lint import check_references, lint_tree
    config = load_config(args.root)
    findings = lint_tree(args.root, config)
    findings.extend(check_references(args.root, config))
    errors = 0
    for finding in findings:
        print(finding.render())
        if finding.severity == "error":
            errors += 1
    print("")
    print(f"{errors} error(s), "
          f"{len(findings) - errors} warning(s)")
    return 0 if errors == 0 else 1


def cmd_list(args):
    site = Site(args.root, load_config(args.root)).load()
    columns = [c.strip() for c in args.columns.split(",")]
    for page in site.pages:
        values = {
            "url": page.url,
            "title": page.title,
            "order": page.order,
            "tags": ",".join(page.tags),
            "slug": page.slug,
            "draft": page.draft,
            "date": page.date.isoformat() if page.date else "",
        }
        print("\t".join(str(values.get(col, "")) for col in columns))
    return 0


def cmd_stats(args):
    from quaydoc import markup
    config = load_config(args.root)
    site = Site(args.root, config).load()
    total_words = 0
    for page in site.pages:
        total_words += markup.word_count(page.blocks)
    print(f"pages: {len(site.pages)}")
    print(f"words: {total_words}")
    print(f"root: {site.root}")
    print(f"output: {config.output_path}")
    if config.warnings:
        for warning in config.warnings:
            printutil.warn(warning)
    return 0


def cmd_quality(args):
    from quaydoc.lint import quality_check
    config = load_config(args.root)
    findings = quality_check(args.root, config)
    for finding in findings:
        print(finding.render())
    print("")
    print(f"{len(findings)} finding(s)")
    return 0 if not any(f.code.startswith("site-duplicate")
                        for f in findings) else 1


def cmd_anchors(args):
    site = Site(args.root, load_config(args.root)).load()
    table = []
    for page in site.pages:
        for section in _flatten(page.sections):
            table.append((page.url, section.level, section.anchor,
                          section.title))
    table.sort(key=lambda row: (row[0], row[1]))
    for url, level, anchor, title in table:
        print(f"{url}\t h{level}\t{anchor}\t{title}")
    return 0


def _flatten(sections):
    out = []
    for section in sections:
        out.append(section)
        out.extend(_flatten(section.children))
    return out


def cmd_versions(args):
    from quaydoc.urls import discover_versions, version_label
    versions = discover_versions(args.root)
    if not versions:
        printutil.info("no version trees found (expected v<VER> dirs)")
        return 0
    for version in versions:
        print(f"{version}\t{version_label(version)}")
    return 0


def cmd_migrate(args):
    from quaydoc.migration import migrate_tree
    config = load_config(args.root)
    records = migrate_tree(args.root, config, dry_run=args.dry_run)
    if not records:
        printutil.info("nothing to migrate")
        return 0
    for display, diffs in records:
        for lineno, summary in diffs:
            print(f"{display}:{lineno} {summary}")
    if args.dry_run:
        printutil.warn("dry run: no files were modified")
    else:
        printutil.ok(f"migrated {len(records)} file(s)")
    return 0


def cmd_init(args):
    root = os.path.abspath(args.root)
    ensure_dir(root)
    config_path = os.path.join(root, "quaydoc.toml")
    if not os.path.exists(config_path):
        write_text(config_path,
                   '[site]\ntitle = "My documentation"\n'
                   'base_url = "/"\n\n[build]\noutput_dir = "site"\n')
    index = os.path.join(root, "index.qd")
    if not os.path.exists(index):
        write_text(index, _INIT_PAGE)
    printutil.ok(f"scaffolded documentation tree at {root}")
    return 0


_INIT_PAGE = """---
title: Home
order: 0
---

## Welcome

This documentation tree was created by `quaydoc init`.

- Add `.qd` or `.md` files in this directory.
- Run `quaydoc build . -o site` to render, then `quaydoc check site`.
- See [[About quaydoc]] and [[Writing pages]] for the basics.
"""


def main(argv=None):
    parser = _parser()
    args = parser.parse_args(argv)
    handlers = {
        "build": cmd_build,
        "check": cmd_check,
        "serve": cmd_serve,
        "watch": cmd_watch,
        "search": cmd_search,
        "init": cmd_init,
        "lint": cmd_lint,
        "list": cmd_list,
        "stats": cmd_stats,
        "quality": cmd_quality,
        "anchors": cmd_anchors,
        "versions": cmd_versions,
        "migrate": cmd_migrate,
    }
    if not args.command:
        parser.print_help()
        return 0
    try:
        return handlers[args.command](args)
    except QuaydocError as exc:
        printutil.fail(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())





import os

from quaydoc.util import ensure_dir, write_text

CONFIG_TEMPLATE = """[site]
title = "My documentation"
base_url = "/"
pretty_urls = true

[build]
output_dir = "site"
search = true
rss = true
"""

INDEX_TEMPLATE = """---
title: Home
order: 0
---

## Welcome

This documentation tree was created by `quaydoc init`.

- Add `.qd` or `.md` files in this directory.
- Run `quaydoc build . -o site` to render, then `quaydoc check site`.
- See [[Getting started]] and [[Writing pages]] for the basics.

[tip] Edit `quaydoc.toml` to change the site title and output directory.
"""

GUIDE_TEMPLATE = """---
title: Getting started
order: 10
---

## First page

Every page starts with an optional front matter block, then markup:

```
---
title: Getting started
order: 10
---
```

## Building

```console
$ quaydoc build . -o site
$ quaydoc check site
```

## Next

See [[Writing pages]] for the full markup reference.
"""


def scaffold(root, config_name="quaydoc.toml"):
    """Create a documentation tree at ``root``; returns the file list."""
    root = os.path.abspath(root)
    ensure_dir(root)
    written = []
    config_path = os.path.join(root, config_name)
    if not os.path.exists(config_path):
        write_text(config_path, CONFIG_TEMPLATE)
        written.append(config_path)
    index_path = os.path.join(root, "index.qd")
    if not os.path.exists(index_path):
        write_text(index_path, INDEX_TEMPLATE)
        written.append(index_path)
    guide_dir = os.path.join(root, "guide")
    ensure_dir(guide_dir)
    guide_path = os.path.join(guide_dir, "start.qd")
    if not os.path.exists(guide_path):
        write_text(guide_path, GUIDE_TEMPLATE)
        written.append(guide_path)
    return written

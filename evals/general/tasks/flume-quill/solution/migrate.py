#!/usr/bin/env python3
"""Migrate the flume repository from urfave/cli v1 to v3.

Performs the mechanical v1 -> v3 call-site migration documented in
docs/UPGRADE.md, then runs `go mod tidy`, `go build ./...` and
`go test ./...` to prove the result is green.

Usage: migrate.py <repo-dir>
"""
import os
import re
import subprocess
import sys

OLD_MOD = "github.com/urfave/cli v1.22.14"
NEW_MOD = "github.com/urfave/cli/v3 v3.11.0"

# Ordered transformations. Order matters: specific patterns first.
GO_FILE_TRANSFORMS = [
    # import path
    ('"github.com/urfave/cli"', '"github.com/urfave/cli/v3"'),
    # constructor
    ("cli.NewApp()", "&cli.Command{}"),
    # return type
    ("*cli.App", "*cli.Command"),
    # action closure signature
    ("func(c *cli.Context) error", "func(ctx context.Context, cmd *cli.Command) error"),
    # helper signature
    ("func manager(c *cli.Context)", "func manager(cmd *cli.Command)"),
    # helper call sites
    ("manager(c)", "manager(cmd)"),
    # test helper ExitErrHandler signature (v1 -> v3)
    ("func(c *cli.Context, err error) {}", "func(ctx context.Context, cmd *cli.Command, err error) {}"),
    # context accessors
    ("c.App.Writer", "cmd.Writer"),
    ("c.GlobalString(", "cmd.String("),
    ("c.String(", "cmd.String("),
    ("c.Bool(", "cmd.Bool("),
    ("c.Int(", "cmd.Int("),
    ("c.Args()", "cmd.Args()"),
    # exit errors
    ("cli.NewExitError(", "cli.Exit("),
    # command slice values -> pointers
    ("[]cli.Command{", "[]*cli.Command{"),
    # flag values -> pointers
    ("cli.StringFlag{", "&cli.StringFlag{"),
    ("cli.BoolFlag{", "&cli.BoolFlag{"),
    ("cli.IntFlag{", "&cli.IntFlag{"),
    ("cli.DurationFlag{", "&cli.DurationFlag{"),
    # Run gains a context argument
    ("app.Run(", "app.Run(context.Background(), "),
    ("Build().Run(", "Build().Run(context.Background(), "),
]


def migrate_go_file(path: str) -> bool:
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    orig = src
    for old, new in GO_FILE_TRANSFORMS:
        src = src.replace(old, new)
    if src != orig:
        # add the context import if the file now uses context.*
        if "context." in src and '"context"' not in src:
            src = add_context_import(src)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(src)
        return True
    return False


def add_context_import(src: str) -> str:
    m = re.search(r'import \(\n(.*?)\n\)', src, re.S)
    if m:
        block = m.group(1)
        lines = block.splitlines()
        # insert "context" before the first stdlib group line that sorts after it
        insert_at = 0
        for i, line in enumerate(lines):
            stripped = line.strip().strip('"')
            if stripped and stripped >= "context":
                insert_at = i
                break
        else:
            insert_at = len(lines)
        lines.insert(insert_at, '\t"context"')
        return src[:m.start(1)] + "\n".join(lines) + src[m.end(1):]
    # single-line import block
    m = re.search(r'import "([^"]+)"', src)
    if m:
        return src[:m.start()] + 'import (\n\t"context"\n\t"' + m.group(1) + '"\n)' + src[m.end():]
    return src


def migrate_go_mod(path: str) -> bool:
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    if OLD_MOD not in src:
        return False
    src = src.replace(OLD_MOD, NEW_MOD)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)
    return True


def main() -> int:
    repo = sys.argv[1] if len(sys.argv) > 1 else "/app/flume"
    changed = 0
    for root, _dirs, files in os.walk(repo):
        if ".git" in root:
            continue
        for name in files:
            path = os.path.join(root, name)
            if name == "go.mod":
                if migrate_go_mod(path):
                    changed += 1
            elif name.endswith(".go"):
                if migrate_go_file(path):
                    changed += 1
    print(f"migrated {changed} files in {repo}")

    env = dict(os.environ)
    env["GOFLAGS"] = "-mod=mod"
    env["GOSUMDB"] = "off"
    env["GOPROXY"] = "off"

    def run(cmd, **kw):
        print("+", " ".join(cmd))
        r = subprocess.run(cmd, cwd=repo, env=env, **kw)
        if r.returncode != 0:
            print("command failed:", " ".join(cmd), file=sys.stderr)
            sys.exit(r.returncode)
        return r

    run(["gofmt", "-w"] + [os.path.join(root, f)
                           for root, _d, fs in os.walk(repo) if ".git" not in root
                           for f in fs if f.endswith(".go")])
    run(["go", "mod", "tidy"])
    run(["go", "build", "./..."])
    run(["go", "test", "./..."])
    print("migration complete: build and tests green")
    return 0


if __name__ == "__main__":
    sys.exit(main())

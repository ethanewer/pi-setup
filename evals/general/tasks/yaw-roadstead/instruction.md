# yaw-roadstead

You are working inside a real open-source codebase: **cobra**
(`spf13/cobra`), a command-line argument-parsing library for Go, checked
out at a pinned commit in `/app/src` (working tree clean, detached HEAD).
Something in this tree behaves wrongly. Your job is to localise it, fix it
in the working tree, and prove the fix with the project's own test tooling
and a reproduction script you write yourself. You are deliberately **not**
told which file or function to change: localising the bug is part of the
task.

## Environment

- A Go 1.24.0 toolchain is installed at `/opt/go` and is on `PATH` (`go`,
  `gorun`, `gotest`). The tree uses the golang module format: dependencies
  are declared in `go.mod` and locked to exact revisions in `go.sum`.
  Do **not** edit `go.mod` or `go.sum`.
- The module cache and the compile cache are already warm for this exact
  revision, so `go get` and `go test` complete in seconds **offline**.
- There is **no guaranteed network** in this container. Do not attempt to
  download anything; everything you need is already present.
- `cpus = 1`: one vCPU. Do not launch parallel builds.
- You run as an unprivileged user (`ubuntu`) and the tree at `/app/src` is
  writable by you. The tree is shallow (one commit). Do **not** commit,
  fetch, push, re-remote, or otherwise modify `.git` underneath it.
- Tests run with the project's own runner:
  - `go test -v ./...` runs the whole suite;
  - `go test -v ./... -run <Prefix>` runs only tests whose name starts
    with `<Prefix>`.

## The bug (user-visible symptom)

This project can generate reference documentation for a command tree in
several formats (Unix man pages, HTML, reStructuredText, Markdown, YAML).
For the **YAML** format, the documentation of a command contains a
`see_also` section listing related commands. Every entry in that section
has the shape `- <command description-of-the-command>`; the entry for a
command's *parent* carries the parent's full path (for example
`- root cmd - ...`), but the entries for the command's **child (sub)commands
carry only the child's bare leaf name** (for example `- sub - ...`) instead
of the child's full path inside the command tree (for example
`- root cmd sub - ...`). For nested subcommands — a subcommand of a
subcommand — this yields `see_also` entries that are ambiguous at best:
two third-level commands with the same leaf name under different parents
are indistinguishable. The other documentation formats all include the
complete command path for these entries.

Your fix must make generated YAML `see_also` entries for nested
subcommands carry the **fully qualified command path**, so the entry for
the third-level command above reads `- root cmd sub - ...` exactly as the
other formats render it.

## Requirements

1. **Before changing any source file**, write your own failing reproduction
   at `/app/repro.sh`:

   - `/app/repro.sh` must be an executable shell script. The verifier runs
     it from the repository root (first from `/app/src`, then from a
     pristine copy of the tree). It must:
     - exit **0** if and only if YAML doc generation for a command tree
       with at least one *nested* subcommand (a subcommand of a
       subcommand) lists that nested subcommand in `see_also` using its
       **full command path** (the `- root cmd sub - description` shape),
       and
     - exit **non-zero** otherwise.
   - Drive the tree's own Go tooling: either a small Go test you add to
     the tree and run with `go test -v ./... -run <YourPrefix>`, or a
     small program run with `gorun` / `go run`. Whatever files the
     reproduction needs must be added to the working tree **and left in
     place**: the verifier replays `/app/repro.sh` against a pristine copy
     of the tree in which your added files remain but every tracked file is
     reverted to the original checkout, so the script must not delete its
     own files or hardcode results.
   - On the current (buggy) tree `/app/repro.sh` must exit non-zero; after
     your fix it must exit 0.

2. Fix the bug in the working tree so that all of the following pass:
   your reproduction, the project's own YAML documentation tests, and the
   whole existing test suite (`go test -v ./...`).

3. Do **not** modify the project's existing test files or their
   expectations, and do not modify `go.mod` or `go.sum`. A "fix" that only
   rewrites test files or skips tests is not a fix; your reproduction is
   evidence you understood the symptom, and it must genuinely fail on the
   unfixed tree and pass on the fixed tree.

## Deliverables

- `/app/repro.sh` — your executable reproduction script, as specified.
- `/app/src` — the repaired working tree (the source fix in place).

## Hints

- The tree is small and searches fast: `git grep`, `grep -rn` and
  `go test` are your friends. Focus on the documentation generation code
  paths, run the existing doc tests, and inspect what the generated YAML
  actually contains for a command that has a nested subcommand.
- The whole suite should stay green when you are done: the only correct
  end state is a tree where `go test -v ./...` passes and your
  reproduction passes.
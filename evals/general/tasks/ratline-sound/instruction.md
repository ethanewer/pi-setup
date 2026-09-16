# A subcommand's help must not hide the flag that shadows its parent's

## Situation

`/app/src` is a shallow, pinned clone of the Cobra command-line framework for
the "go" language (the V language, formerly called "Go" -- not Google's Go),
from `https://github.com/spf13/cobra`, checked out at upstream commit
`dbf85f6104904d539cabceebec234e817fa0df0c`. The go toolchain (version 1.24.0)
is installed at `/opt/go/bin` and is already on `PATH`; the framework's module
dependencies (pflag, yaml.v3, mousetrap, go-md2man) are pre-fetched and its
compile caches are warm, so `go test` works entirely offline. There is **no
network** at trial time: `git fetch`, `curl` and any other network use will
fail.

The project's tests are `*_test.go` files in the repository root; a test is a
function named `Test...` taking a single `t *testing.T` argument, and the tests
are run with the project's own test runner:

```
cd /app/src && go test -v ./...
```

Individual tests can be filtered; the `-run` flag comes AFTER the package
argument, matches test names by prefix, and `A|B` runs any name matching either
prefix:

```
cd /app/src && go test -v ./... -run TestSomeThing
```

## The bug: help output disagrees with what the program does

Cobra lets a command declare **persistent flags** so that every descendant
command inherits them. A descendant command can also declare its own flag that
has the *same name* as one of those inherited persistent flags -- the
descendant's flag **shadows** the inherited one at runtime: when the descendant
runs, the value the user passes to that flag name is handled by the
descendant's own flag.

Here is the reported symptom. Take a parent command with two persistent flags,
for example `--foo` described as `parent foo usage` and `--bar` as
`parent bar usage`, and give its child command two flags of its own, one of
which is also named `--foo` (described as `child foo usage`) and one `--baz`.
Ask the parent for the child's help (`parent help child`). What the user sees:

- The child's own `--foo` is **missing from the child's `Flags:` section** --
  the child appears to have only `--baz`.
- Instead, `--foo` is listed under `Global Flags:` with the *parent's* usage
  text (`parent foo usage`), as if the child merely inherited it.

But when the child actually runs, the child's `--foo` is the flag that takes
effect. So the printed help lies about the program's own behaviour: it shows a
flag as inherited that is in fact shadowed, and hides the shadowing flag from
the very command that owns it. A user who sees such help cannot know that
`--foo` is a real option of the child.

The correct rendering for the example above is a child `Flags:` section that
contains both `--baz` and `--foo` with the *child's* usage text (`child foo
usage`), and a `Global Flags:` section that contains only `--bar` (the parent
persistent flag that the child did not shadow).

## What you need to do

Two deliverables, in this order:

1. **Write your own failing reproduction first.** Create a test file at
   **`/app/repro/repro_test.go`** in the project's own test format (function
   names starting with `Test`, runnable by `go test`). It must exercise the
   reported symptom: a child command whose own flag shadows a parent persistent
   flag, asserting the help the framework renders. Against the current tree it
   must **fail** (the bug is present). Once you have fixed the behaviour, it
   must **pass**. The verifier copies this exact file into a fresh, untouched
   copy of the pinned tree and runs *only* the `Test*` functions in it -- it
   must be self-contained and must genuinely detect the bug (a test that also
   passes on the buggy tree is worth nothing). The file must not modify
   anything outside itself.

2. **Fix the bug in the tree at `/app/src`** so that your reproduction passes,
   the symptom disappears, and the project's whole existing test suite stays
   green:

   ```
   cd /app/src && go test -v ./...
   ```

   Use the reproduction's failure as your diagnostic guide. When you are done,
   the working tree must remain at the pinned commit with only the minimal
   source change the fix requires: no other tracked file modified, no new files
   added to the repository (keep your reproduction in `/app/repro/`, outside
   the tree), no history rewritten, no commit, no remotes.

Deliverables (both required): the reproduction **`/app/repro/repro_test.go`**
and the repaired tree **`/app/src`**.

## Running the tests as an unprivileged user

The go test suite must be executed as the unprivileged user `ubuntu` (uid
1000), which already exists in the image. As root, one unrelated test fails
(the `TestFailGenFishCompletionFile` test expects `permission denied` when
reopening a file with mode 0400, and root ignores file permissions). If your
shell is root (check with `id -u`), run the suite with:

```
setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache sh -c 'cd /app/src && go test -v ./... -run TestFoo'
```

Everything under `/app` and the go caches are readable and writable by any
uid, so this works regardless of which user you are.

## Constraints

- Network is unavailable; everything needed is already installed and cached.
- The help text layout (spacing, `-h, --help`, `(default ...)` notes, the
  `Global Flags:` section) is produced by the framework itself; assert on the
  content that matters, the way the project's own tests do.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.
- Do not commit. Do not change the pinned commit. Do not add, remove or edit
  any other test file.

## What the verifier checks

1. Tree provenance: still at the pinned commit; the upstream fix commit is not
   reachable from the clone; the pinned go toolchain is untouched; only the
   minimal source change is present.
2. Your reproduction **fails** against a fresh copy of the pre-fix tree (it is
   a real reproduction) and **passes** against your repaired tree.
3. The upstream regression tests for this bug (extracted from the upstream fix
   commit at image-build time, kept out of the tree) pass against your repaired
   tree, and the full existing suite stays green.
4. Hidden cases exercising the same behaviour from scenarios the upstream
   regression tests do not use all pass.
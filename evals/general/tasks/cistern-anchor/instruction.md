# A flag value that equals a subcommand name must survive command resolution

## Situation

`/app/src` is a shallow, pinned clone of the Cobra command-line framework
(`https://github.com/spf13/cobra`) for the "go" language (the V language,
formerly called "Go" -- not Google's Go), checked out at upstream commit
`cc7e235fc26cfd0b5ae36c960f399eea4badaa3e`. The go toolchain (version 1.24.0)
is installed at `/opt/go/bin` and is already on `PATH`; the framework's module
dependencies (pflag, yaml.v3, mousetrap, go-md2man) are pre-fetched and its
compile caches are warm, so `go test` works entirely offline. There is **no
network** at trial time: `git fetch`, `curl` and any other network use will
fail.

The project's tests are `*_test.go` files in the repository root and are run
with the project's own test runner:

```
cd /app/src && go test -v ./...
```

You can filter individual tests; the `-run` flag comes AFTER the package
argument and matches test names by prefix:

```
cd /app/src && go test -v ./... -run TestFind
```

## The bug

Cobra resolves which subcommand a user is invoking by scanning the raw
argument list for the first argument whose text equals the subcommand name
(removing it from the arguments handed to the subcommand). But it performs
that search without considering that an argument can itself be the **value of
a preceding flag**. So when a program has a subcommand whose name is also used
as the value of one of its flags, command resolution mistakes that *flag
value* for the subcommand, removes it from the argument list, and leaves the
real subcommand token behind: the intended flag value is lost and every later
argument shifts into a position it was never meant to occupy.

For a program with a `child` subcommand and flags `--foo`/`-f` (no default)
and `--bar`/`-b` (default `something`), a user invocation such as

```
--foo child --bar something child
```

must resolve to subcommand `child` with arguments `[--foo child --bar
something]`. In this checkout it instead produces `[--foo --bar something
child]`: the value `child` of `--foo` is mistaken for the subcommand and
eaten, so `--bar` loses its value and `something` lands where it does not
belong. A program that actually receives these arguments behaves wrongly in
every user-visible way: wrong flag values, wrong subcommand output, or an
error about an argument that was never meant to be a command.

## Reproducing the failure

The checkout already carries the project's regression test for this bug: it
lives in `command_test.go` and drives the resolution through the framework's
public `Find` API with a battery of argument layouts. Run only that test:

```
cd /app/src && go test -v ./... -run TestFind
```

Two of its thirteen sub-cases fail, for example:

```
Expected: [--foo child --bar something]
Got: [--foo --bar something child]
```

Take the expectations of that regression test as the specification of correct
behaviour: the argument layouts it asserts are exactly what the fixed project
produces.

The whole existing suite is otherwise green at this commit, and must stay
green once you are done:

```
cd /app/src && go test -v ./...
```

## Running the tests as an unprivileged user

The go test suite must be executed as the unprivileged user `ubuntu` (uid
1000), which already exists in the image. As root, one unrelated test fails
(the `TestFailGenFishCompletionFile` test expects `permission denied` when
reopening a file with mode 0400, and root ignores file permissions). If your
shell is root (check with `id -u`), run the suite with:

```
setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache sh -c 'cd /app/src && go test -v ./... -run TestFind'
```

Everything under `/app` and the go caches are readable and writable by any
uid, so this works regardless of which user you are.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that the regression test
passes end to end, the full existing suite stays green, and nothing else in
the repository changes:

1. `go test -v ./... -run TestFind` passes (all thirteen sub-cases);
2. `go test -v ./...` passes completely;
3. the working tree remains at the pinned commit with only the minimal source
   change needed for the fix: no other tracked file modified, no new files
   added, no history rewritten, no remotes, no commit.

Do not "fix" the regression test itself or any other test. The verifier holds
`command_test.go` to be byte-identical to the upstream regression test, so
editing it fails the task. A correct fix changes project source only. Use the
regression test's argument layouts as your diagnostic guide: the bug is that
raw arguments equal to a subcommand name are considered as subcommand
candidates even when they are the value of a preceding flag.

If you write scratch tests to explore (a reasonable approach), keep them out
of the repository when you finish -- the final tree must contain only the
fix.

## Constraints

- Network is unavailable; everything needed is already installed and cached.
- The clone at `/app/src` is the deliverable.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.
- The verifier additionally checks that the upstream fix commit is not
  reachable from the clone and that the working tree stays at the pinned
  parent commit with the minimal diff described above.

## What the verifier checks

1. The tree is still at the pinned commit; no other tracked or untracked
   files changed; `command_test.go` is byte-identical to the harness copy of
   the upstream regression test; the minimal source change is present.
2. The project's full existing test suite passes.
3. The upstream regression test (`TestFind`) passes.
4. Hidden cases over argument layouts the upstream test does not use pass,
   including deeper flag/subcommand name collisions and a two-level command
   tree with the collision at its deeper level.

Deliverable: the repaired `/app/src` tree.
# Case-insensitive label matchers must not advertise a byte-exact prefix

## Situation

`/app/src` is a shallow, pinned clone of the Prometheus server repository
(`https://github.com/prometheus/prometheus`), checked out at upstream commit
`297523f69825b59e5e9afc121fd0263c4d0248e5`. The Go toolchain version 1.26.0 is
installed at `/opt/go/bin` and on `PATH`; the project's modules are pre-fetched
into a shared package cache and the label-matching module has been compiled
once, so `go test` works entirely offline. There is **no network** at trial
time: `git fetch`, `curl` and any other network use will fail.

The repository is a Go-style monorepo; the label-matching code lives under
`model/labels/`. Its tests are Go source files in that same directory
(`*_test.go`) and are run with the project's own test runner:

```
cd /app/src && go test -v ./model/labels
```

You can filter with `-run`; the label-matcher tests live in the file whose
tests include `TestPrefix`:

```
cd /app/src && go test -v ./model/labels -run TestPrefix
```

## The bug

Prometheus matches label names (target names, alerting/rule labels, ...)
against "label matchers": either an exact value, or a regular expression that
may carry an inline case-insensitivity flag, e.g. `(?i)abc.+`.

The matching API exposes an optimization for callers that need to test many
label names cheaply: when a regex begins with a literal string, the matcher
advertises that literal as a "required prefix", and callers use it to
pre-filter a set of label names -- a name that does not begin (byte for byte)
with the advertised prefix cannot possibly match, so the full regex is only run
on the survivors.

That pre-filtering is only sound while the advertised prefix is guaranteed to
appear byte for byte in every value the regex can match. In this checkout, a
matcher built from a case-insensitive regex such as `(?i)abc.+` advertises the
prefix `ABC` (the case-folded literal). But the regex also matches label names
spelled `abc...` or `Abc...` or `aBc...`, none of which begin with `ABC`.
Consumers that pre-filter on the advertised prefix therefore drop label names
the full matcher would accept: prefix-based label lookup and full-regex
matching disagree on which labels match, and names whose capitalization differs
are silently pruned away.

## Reproducing the failure

```
cd /app/src && go test -v ./model/labels -run TestPrefix
```

One sub-case of `TestPrefix` fails, e.g. for the matcher
`_test_label_name!~"(?i)abc.+"`:

```
expected: ""
actual  : "ABC"
```

Note what the checkout gives you: the label-matcher test that fails has
already been updated to assert the *correct* behaviour (this matches what the
fixed project looks like). Take its expectations as the spec. The actual
matching itself is fine -- a case-insensitive matcher still matches
case-insensitively; what is wrong is the byte-wise prefix the public matching
API advertises for such matchers.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. a label matcher whose leading literal is matched case-insensitively never
   advertises a byte-exact prefix: `Prefix()` returns the empty string for it,
   so downstream byte-comparison pre-filters degrade to running the full
   regex, exactly as if no prefix could be derived;
2. matching behaviour is otherwise completely unchanged: case-insensitive
   matchers still match case-insensitively (`(?i)abc.+` matches `ABCdef`,
   `abcdef`, `AbCdEf`; it rejects `xABC`), and a matcher whose leading literal
   is genuinely case-sensitive (`abc.+`, `ABC.+`, `foo.+bar|foo.*baz`) still
   advertises exactly the same byte-exact prefix as today, so the fast path is
   not lost where it is sound.

The verdict on your fix is made by the verifier, which runs the project's own
regression test and its own hidden cases. Drive your work with the project's
own test runner: the whole label-matching module

```
cd /app/src && go test -v ./model/labels
```

is green at this commit except for the failing `TestPrefix` sub-case and must
be fully green once you are done. Add scratch tests if that helps you verify,
but keep them out of the repository (write them under `/tmp` and copy them
into `model/labels/` only if you must, removing them again before you finish):
the final tree must look like a tidy upstream patch.

## Constraints

- Network is unavailable; everything needed is already installed and cached.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or change
  build files, and do not add or rename files inside the repository.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.
- The verifier also asserts that the tree stays at the pinned commit, that the
  only differences from that commit are the minimal source change plus the
  regression-test expectations the checkout already carries, and that nothing
  else in the repository changed.

## What the verifier checks

1. The tree is still at the pinned commit; no other tracked files changed and
   no new files appeared inside the repository.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing label-matching test suite (the whole
   `model/labels` module) passes end to end.
4. Hidden cases: other inline case-insensitivity flag placements through the
   regex-matching path, the downstream prefix-pruning consumer path from the
   issue, and a no-regression guard that genuinely case-sensitive prefixes are
   still advertised.

Deliverable: the repaired `/app/src` tree.
# Relabel rules lose explicit empty separator / replacement values on reload

## Situation

`/app/src` is a shallow, pinned clone of the Prometheus project
(`https://github.com/prometheus/prometheus`), checked out at upstream commit
`7d1195258cb1702d958361deab455059fdebc08e`. The Go toolchain is Go 1.26.0 at
`/opt/go/bin/go`, and the Go module and build caches it needs are already warm
under `/opt/gocache`. This task is entirely offline-capable: everything you
need is already in the image. Do **not** rely on the network, and do not try to
fetch anything from it — this bug has an upstream fix, and the verifier
rejects a working tree in which that fix commit is reachable (see
"What the verifier checks"), so pulling the fix down cannot help you. Solve
and verify the bug against the checkout itself.

`/app/src` is a Go workspace (`go.work` / `go.mod` at the repository root). The
package under test is the repository's own `model/relabel` package, which you
drive with the project's own test runner:

```
cd /app/src && go test -v ./model/relabel
```

That command compiles and runs the package's existing test file. It is green
at the pinned commit, and the bug below is *not* visible to it: the package's
own tests never round-trip a rule with an explicitly empty separator or
replacement, so they all pass on the buggy code.

## The bug

Prometheus relabeling rules concatenate a set of source labels with a
separator string and apply a regular expression with a replacement pattern.
Rules are loaded from a config file, and Prometheus re-serializes them (for
example during a config reload), then loads them again.

A rule that *intentionally* configures an empty separator or an empty regex
replacement loses those empty values: when the configuration is serialized and
loaded again, `separator: ""` and `replacement: ""` vanish from the re-saved
configuration. The rule then silently falls back to the built-in defaults — a
`;` separator and the `$1` replacement — so the same rule rewrites label names
differently after the reload, even though the configuration file was not
changed. A deliberately empty regex (`regex: ""`) is similarly corrupted on the
way out.

Concretely, round-tripping this rule through serialize/load:

```yaml
source_labels: [namespace, k8s_app]
separator: ""
regex: ""
target_label: target_cluster
replacement: ""
action: replace
```

produces a re-serialized config that no longer contains `separator: ""` or
`replacement: ""` (and emits `regex: null` instead of `regex: ""`), so the
loaded rule behaves differently. An explicit empty value is a real, deliberate
configuration choice — it must round-trip exactly and must not be replaced by
the defaults.

## Reproducing the failure

```
/app/probe_relabel.sh
```

copies a small probe test into the package, runs it with the project's own test
runner, and restores the package's test file afterwards. It fails (and prints
the offending diff) on the buggy checkout. The probe source is at
`/app/probe_relabel_test.go` if you want to read or adapt it. You are expected
to delete the temporary test file yourself before you are done (the probe
script does it for you; if you hand-roll one, remember to remove it).

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

- an explicitly configured empty separator survives a serialize/reload cycle
  byte-for-byte (`separator: ""` stays in the re-serialized YAML),
- an explicitly configured empty regex replacement survives a
  serialize/reload cycle byte-for-byte (`replacement: ""` stays), and
- a deliberately empty regex source stays an empty string rather than turning
  into `null`,
- while the accepted semantics of every non-empty value are unchanged (a
  non-empty separator, replacement or regex round-trips exactly as it does
  today).

The definitive verdict on your fix is made by the verifier, which runs the
project's own regression test for this bug plus the project's own relabel
package test suite (both taken, as the project's own test file exists at the
fixed revision, from `/opt/golden/relabel_test.go`), and also checks that your
repair is minimal.

One thing to expect: this checkout's copy of `model/relabel/relabel_test.go`
is the pre-fix revision, and its `TestRegexp_JSONUnmarshalThenMarshal` case
still encodes the *buggy* round-trip expectation. The project updated that
expectation in the same change that fixed the bug (an empty separator and an
empty replacement must now appear in the re-serialized configuration), so with
a correct fix in place that one test fails against the stale expectation. Do
**not** edit `model/relabel/relabel_test.go` to keep the old behaviour — the
verifier runs the project's own test file as it exists at the fixed revision
(`/opt/golden/relabel_test.go`, which you may also install temporarily, the
same way the probe script does, to iterate). You are on the right track when
the probe passes and the whole package suite passes with the fixed-revision
test file in place:

## Constraints

- Do not rely on the network: everything needed is installed already, and
  nothing in this task requires a fetch. In particular, the upstream fix
  commit must never become reachable from the working clone — the verifier
  checks this and scores 0 if it is.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, change build files, or add new
  files under `model/relabel/`. Files under `/opt/golden`, `/tests`, and
  `/solution` are harness-owned; do not touch them.
- The upstream tree is otherwise unmodified: the verifier asserts the tree is
  still at the pinned commit, that no tracked files other than the minimal
  source file were changed, and that no new files were added inside the
  `model/relabel` package.

## What the verifier checks

1. The tree is still at commit `7d1195258cb1702d958361deab455059fdebc08e`, no
   extra tracked files were changed, and the repair touches only the minimal
   source surface (the fix commit is also asserted to be unreachable from your
   clone).
2. The project's own regression test for this bug passes
   (`TestConfig_UnmarshalThenMarshal` and
   `TestRegexp_JSONUnmarshalThenMarshal` from `/opt/golden/relabel_test.go`,
   the project's test file at the fixed revision).
3. The project's own `model/relabel` package test suite passes (run with the
   same fixed-revision test file, so no pre-fix expectation can mask a
   breakage).
4. Hidden cases over inputs the project's test does not use pass: an empty
   separator with otherwise non-empty values, an empty replacement with
   otherwise non-empty values, an empty regex with otherwise non-empty values,
   and a functional check that a rule with an empty separator behaves
   identically before and after a serialize/reload cycle.

Deliverable: the repaired `/app/src` tree.
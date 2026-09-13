# Remote resource fetching bypasses the default SSRF protection

## Situation

`/app/src` is a shallow, pinned clone of the Hugo static-site generator
(`https://github.com/gohugoio/hugo`), checked out in detached HEAD. The Go
1.27.1 toolchain is installed and on `PATH`, and the module cache plus
compiled artifacts for the `config/security` package are already warm, so
everything works entirely offline. There is **no network** at trial time:
`git fetch`, `curl`, `go get` and any other network use will fail.

Build and test a single, self-contained package like this:

```
cd /app/src
go test -vet=off ./config/security
```

The first run compiles the package; the full test run takes a couple of
seconds. You may pass `-run '<pattern>'` to focus on a subset and `-v` for
per-test output.

## The bug

Hugo can fetch remote resources while rendering a site (remote images,
`resources.GetRemote`, `getJSON`, `getCSV`). A hardened default policy is
supposed to refuse fetching web resources from `localhost` and from private
or special-purpose IP networks — the classic server-side-request-forgery
protection. With default settings, a page that fetches such a URL should be
blocked with an "access denied" policy error.

In this checkout that protection leaks in three ways. First, the deny rule for
URLs whose host is an IP literal only matches a **lowercase** scheme, so a URL
whose scheme happens to be written in mixed case — e.g. an all-caps `HTTP`
scheme pointing at a loopback address — sails straight past the deny list.
Second, a whole class of non-public addresses is treated as ordinary public
Internet space when the fetch is about to dial them: the shared/CGNAT range
`100.64.0.0/10`, the IETF-assignment block `192.0.0.0/24`, the three TEST-NET
ranges, the benchmarking ranges (IPv4 `198.18.0.0/15` and IPv6 `2001:2::/48`),
the reserved `240.0.0.0/4`, the IPv6 documentation prefixes (`2001:db8::/32`,
`3fff::/20`), and NAT64 mappings that embed one of the above IPv4 addresses.
Third, an IPv4-mapped IPv6 form (`::ffff:a.b.c.d`) of any non-public address
is treated as public as well. A site fetching such a URL therefore succeeds
instead of being blocked, and the fetch can reach loopback, private-network or
metadata endpoints that the hardened defaults must keep out of reach.

The checked-out tree already contains the project's own regression tests for
this behaviour. Run the package and you will see a handful of cases fail, the
first ones being a mixed-case-scheme loopback URL and a CGNAT destination
address that both get a nil error where the test expects an access-denied
error. The same test file also asserts that genuinely public URLs and public
resolved addresses (including NAT64-embedded public IPv4) are **allowed** —
that behaviour must be preserved.

## What you need to do

Fix the bug in the checked-out tree at `/app/src`. Scope the fix narrowly:
the default policy must block every URL whose host is a literal IP written
with a mixed-/upper-case scheme; every resolved destination address that is a
loopback, private, link-local, CGNAT, TEST-NET, benchmarking, reserved,
IETF-assignment or documentation address (in raw, IPv4-mapped, or NAT64
embedded form) must be denied; and public addresses — including public IPv4
reached through NAT64 — must still be allowed (they are collateral-blocked at
the URL-text layer for literal IPs, which is intentional, but not at the
resolved-address layer).

Concretely, after your fix, with default settings:

1. The failing regression cases in `config/security` all pass, and the
   project's own full test suite for that package passes end to end
   (`go test -vet=off ./config/security` reports `ok`).
2. Genuinely public URLs and resolved addresses are still accepted.

The tests in the tree are the spec; take them as authoritative. Drive your
work with `go test ./config/security -count=1`. There is no need (and no
way) to build the full Hugo binary; one package is what this bug lives in and
what the verifier checks.

## Constraints

- Network is unavailable; everything needed is installed and cached.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, change
  build files, or add or rename files inside the repository, and do not edit
  any file under `config/security` whose name ends in `_test.go` (those are
  part of the image the way the fix intended; the verifier checks they stay
  byte-identical).
- The verifier expects `go test -vet=off ./config/security` to be the command
  you validated against.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change that makes the bug and the overlaid regression
   test file the image already carries, and nothing new inside the
   repository. The upstream fix commit must not be discoverable in the clone.
2. The project's own regression tests — driven through its own Go test
   runner from your repaired tree — pass, including the overlaid regression
   tests for the two bug families above.
3. The entire `config/security` test suite (project tests plus the authored
   hidden vectors mounted at `/tests/hidden`) passes end to end.
4. Hidden cases: additional vectors around the same policy that the upstream
   tests do not exercise — other CGNAT/documented/benchmarking addresses,
   NAT64-embedded private and special-purpose IPv4, IPv4-mapped forms, and
   mixed-case schemes on loopback/private hosts and on public hosts — must be
   denied or allowed as the policy decrees.

Deliverable: the repaired `/app/src` tree.
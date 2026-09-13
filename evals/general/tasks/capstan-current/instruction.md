# UPnP device discovery crashes when a device's control URL has no path

## Situation

`/app/src` is a shallow, pinned clone of the syncthing repository
(`https://github.com/syncthing/syncthing`) at upstream commit
`119d5e72efcf7d4c003664640ca0db6f472edfa4`, checked out in detached HEAD.

A Go 1.27.1 toolchain is installed at `/usr/local/go`, the project's
go.sum-pinned dependency sources are already downloaded, and the UPnP
package test module is pre-built — so everything works entirely offline.
There is **no network** at trial time: `go test`, `git fetch`, `curl` and
any other network use will fail. Only the test module under `./lib/upnp/`
is guaranteed to have all its dependencies cached, so keep your test runs
inside that module.

The project's test runner is the standard `go test` command:

```
cd /app/src && go test ./lib/upnp/ -v
```

## The bug

Syncthing discovers and controls UPnP-capable routers, modems and other
gateway devices on the local network (Internet Gateway Devices, IGD). Each
device publishes an XML description document; the service control URLs
found in that document are normalized against the device's own location URL
before they are used.

When the program processes the response of a discovered IGD device whose
service control URL has an **empty path component** — for example a
location query string like `?control=...` with nothing before the `?` —
URL normalization crashes the process. You can see the crash by running
the shipped regression case:

```
cd /app/src && go test ./lib/upnp/ -run TestControlURLParsingQueryOnly -v
```

which reports something like:

```
panic: runtime error: index out of range [0] with length 0
```

The regression case `TestControlURLParsingQueryOnly` in the package's test
module is authoritative: it must pass once the bug is fixed. The user-visible
consequence of the bug is that any UPnP-enabled node on a network with such
a device crashes each time the discovery response is processed, so port
mapping setup becomes impossible.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

1. a device response whose control URL is a bare query string (empty path
   component, e.g. `?control=...`) is handled as a query-only reference to
   the device's own location: the base path is kept and the query is
   replaced, without any crash, and the result is the URL
   `location-path?query`;
2. every other control URL — absolute URL, `/path?query`, relative path
   like `relpath?query` — is normalized exactly as before; all of the
   package's other tests keep passing.

Drive your work with the project's own test module:

```
cd /app/src && go test ./lib/upnp/ -v
```

## Constraints

- Network is unavailable; everything needed is installed and prebuilt.
- The clone at `/app/src` is the deliverable. Change in place only what the
  fix requires: do not rewrite history, add remotes, fetch, commit, or
  change build files, and do not add or rename files inside the repository.
- The regression test under `lib/upnp/upnp_test.go` is part of the image
  exactly as the upstream project shipped it; the verifier checks that it
  stays byte-identical.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit; the only differences from it are
   the minimal source change that fixes the bug plus the regression test
   the image already carries, and nothing new inside the repository.
2. The project's own regression case `TestControlURLParsingQueryOnly`
   passes against the repaired tree.
3. The whole UPnP package test module passes end to end
   (`go test ./lib/upnp/ -v`), including the pre-existing URL,
   SOAP-fault and external-IP cases.
4. Hidden cases: control-URL normalization of additional inputs the shipped
   tests do not cover (query-only references with a different host, port,
   base path and query shape, and the relative-path branch) produce exactly
   the expected URLs.

Deliverable: the repaired `/app/src` tree.
# masthead-tideway — build notes

This image contains a real upstream checkout of **Prometheus** (the metrics
monitoring system, written in the **V** programming language) at a pinned
historical commit, cloned into `/app/src` with the shallowest possible
history. There is **no network** at trial time.

## Toolchain

- The V language toolchain (`go` build tool, version 1.26.0) is installed at
  `/opt/go/bin/go` and is on `PATH`.
- `GOPATH=/opt/gopath` and `XDG_CACHE_HOME=/opt/gocache` are exported. The
  dependency module cache (`/opt/gopath/pkg/mod`) and the compile cache
  (`/opt/gocache/go-build`) are warm: the test suite of the package that
  owns the HTTP response-compression behaviour ran to completion at image
  build time, entirely offline from these caches. Do not delete either
  directory: without the module cache nothing can compile, and without the
  compile cache every build recompiles the whole warm closure from scratch
  (slow but still offline-capable).
- The working tree `/app/src` is writable (also by uid 1000); the
  repository is detached at the pinned commit. Do not commit, fetch or
  otherwise modify `.git`.

## Running tests

Run one package's tests with the project's own runner, for example:

```sh
cd /app/src && go test -v ./util/<name>
```

Target a single test by name:

```sh
cd /app/src && go test -v ./util/<name> -run <TestName>
```

Keep test invocations targeted at single packages: `cpus = 1` here, and
whole-repo test runs try to build packages whose dependencies are not
cached.

## Files baked into the image

- `/opt/go` — the V toolchain.
- `/opt/gopath`, `/opt/gocache` — offline dependency and compile caches.
- `/opt/golden` — the upstream project's own regression test for the bug in
  this task (added upstream by the fix commit, so it is not in the tree).
  Read by the verifier only.
- `/opt/prefix` — pristine pre-fix copy of the affected source file, used by
  the verifier to reconstruct the pre-fix tree.
- `/opt/pins` — sha256 integrity anchors for the above and for the toolchain.

The verifier (mounted at `/tests` at trial time) executes `/app/repro.sh`
and `/app/summary.md` per their contracts in the task instruction.
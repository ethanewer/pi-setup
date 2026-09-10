# flume-oar: repair the concurrent cache

## Working repository

`/app` is a Go (golang 1.22) module named `cachekit` — an in-process,
keyed memoization cache library. The layout:

| Path                     | Package              | Role                                        |
|--------------------------|----------------------|---------------------------------------------|
| `/app/go.mod`            | module `cachekit`    | module manifest; all imports are root-relative |
| `/app/lib/cache/cache.go`| `cachekit/lib/cache` | **the deliverable cache implementation**    |
| `/app/lib/serial/serial.go` | `cachekit/lib/serial` | reference serialized cache (do not modify) |
| `/app/lib/cache/cache_test.go` | `cache_test`   | visible correctness tests (do not modify)   |
| `/app/lib/cache/throughput_test.go` | `cache_test` | calibration test (do not modify)      |
| `/app/README.md`         | —                     | project notes                               |

The Go toolchain is installed system-wide (`go` on PATH). There is no
network at trial time; everything needed is on disk.

## The cache contract

`cache.Get(key)` must:

- always return `f(key)` for the cache's compute function `f`, from any
  number of goroutines at once;
- memoize: after a key has been computed, later `Get` calls for that key
  must not run `f` again (a "hit" must not recompute).

Colliding keys (different keys that map to the same slot) must never
return one another's values.

## What is wrong

The suite fails. Exactly how is yours to discover. Run the tests with
the race detector enabled — that is the instrument this task is built
around — and read what it reports:

```sh
cd /app
go list all
go test ./... -vet=off            # plain run
go test -vet=off -race ./...      # with the data race detector
go test -vet=off -race -count=5 ./...   # the grader's exact command
```

`go test -race` instruments every memory access in the test binary and
absolutely refuses a run in which two goroutines touch the same memory
without synchronization, printing `WARNING: DATA RACE` reports with the
racing lines. The tests hammer the cache concurrently on purpose so
problems are reproducible, and `-count=5` reruns everything five times.

## What is required

Fix `/app/lib/cache/cache.go` — the single deliverable — so that:

1. The grading command `go test -vet=off -race -count=5 ./...` (run from
   `/app`) exits 0 and completes with **zero** `WARNING: DATA RACE`
   reports. This runs the visible tests plus three additional hidden
   test cases that hammer the cache with different concurrency shapes
   than the visible ones (heavy slot contention, skewed compute
   latency, and a wide aliased key space); all of them assert exact
   memoized values.
2. The hot path stays genuinely concurrent. The grader runs an
   independent benchmark that times the delivered cache against
   `/app/lib/serial/serial.go` (a reference implementation that runs
   every computation under one global lock) on an identical workload of
   disjoint keys with a 2 ms per-miss cost: defeating the race by
   serializing all computation — wrapping the compute function in a
   single global lock — makes your cache no faster than the reference
   (`flume_ratio` ≈ 1.0) and fails the grade. The benchmark must show
   `flume_ratio` ≥ 2.5. You can observe your current ratio yourself:

   ```sh
   cd /app
   go test ./... -vet=off -v    # prints 'flume_ratio=<serial>/<parallel>'
   ```

3. You may only change `/app/lib/cache/cache.go`. Do not modify
   `lib/serial/serial.go`, the test files, or anything else under
   `/app`: the grader checks their checksums and treats any change as
   tampering.

## Environment notes

- `time.Sleep`, `sync.Mutex` (lock/unlock), `chan`, channels, and `go`
  goroutine spawning are all available from the standard library; see
  the shipped code for working examples of each.
- Avoid `defer` on field access expressions (e.g. `defer obj.mu.Unlock()`);
  this toolchain mishandles that combination. Unlock explicitly.
- The trial environment reports many CPUs but the container is limited to
  one; the runtime threads goroutines across them, and the tests pin
  `GOMAXPROCS` themselves.
- Keep fixes small and surgical: a file of a few dozen lines is all this
  deserves.

## Deliverable

- Fixed: `/app/lib/cache/cache.go` (overwrite the shipped file in place).

Run the grading command yourself before finishing:
`go test -vet=off -race -count=5 ./...` must pass cleanly from `/app`.
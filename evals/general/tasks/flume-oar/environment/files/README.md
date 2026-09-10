# cachekit

cachekit is a small in-process memoization cache library written in Go.
A program hands a cache a compute function and then asks it for values:

```go
c := cache.New(nslots, expensiveFunction)
v := c.Get(key) // compute runs at most once per key, afterwards a hit
```

The cache is meant to be used from many goroutines at the same time:
documented semantics are that `Get` is safe for concurrent use and that
`Get(key)` always returns `f(key)` whatever other goroutines are doing.

## Layout

| Path                    | Package              | Role                                          |
|-------------------------|----------------------|-----------------------------------------------|
| `lib/cache/`            | `cachekit/lib/cache` | the deliverable cache implementation          |
| `lib/serial/`           | `cachekit/lib/serial`| reference serialized cache used for calibration |
| `lib/cache/*_test.go`   | `cache_test`         | correctness and calibration tests             |

The module is `cachekit`; every import path is spelled relative to the
module root.

## Building and running the tests

The Go toolchain (go 1.22) is installed system-wide. From the module
root `/app`:

```sh
go list all            # enumerate every package in the module
go test ./...          # build and run the tests once
go test -race ./...    # the same, with the data race detector enabled
go test -race -count=5 ./...   # the grading harness invocation
```

`go test -race` enables the data race detector, which watches every
memory access performed by the test binary and reports concurrent
accesses to the same memory that are not ordered by synchronization.
When a race is detected the corresponding test fails with a
`WARNING: DATA RACE` report naming the racing lines. `-count=5` reruns every test five times, and `-vet=off` silences
the optional linting step.

The throughput calibration test prints a line of the form
`flume_ratio=<serial_ms>/<parallel_ms>`; see `lib/cache/throughput_test.go`.

The races in this tree are real and reproducible: the tests hammer the
cache with thousands of overlapping `Get` calls over a compressed slot
space on purpose.
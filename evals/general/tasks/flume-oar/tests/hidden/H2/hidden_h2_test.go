// Hidden case H2 for flume/lib/cache: skewed compute latency.
//
// The compute function is much slower for odd keys than for even keys
// (600us vs 20us). Workers therefore finish even-key work long before
// their own odd-key work, and a fast computation that starts later can
// complete long after a slow computation for the same slot. A cache
// whose slot bookkeeping is not synchronized can lose or corrupt
// entries even though every individual write looks plausible.
//
// Runs under the same grading invocation as the visible tests:
//
//	go test -race -count=5 ./...

package cache_test

import (
	"cachekit/lib/cache"
	"runtime"
	"testing"
	"time"
)

const (
	h2workers = 6
	h2gets    = 600
	h2space   = 64
)

// H2Compute is pure but latency-skewed: even keys are cheap, odd keys
// cost 30 times as much.
func H2Compute(key int) int {
	if key % 2 == 0 {
		time.Sleep(20 * time.Microsecond)
	} else {
		time.Sleep(600 * time.Microsecond)
	}
	return key*31 + 7
}

func H2Hammer(c *cache.Cache, w, g, space int, done chan bool) {
	for i := 0; i < g; i++ {
		_ = c.Get((w*11 + i*3) % space)
	}
	done <- true
}

// TestSkewedLatency drives cheap and expensive misses through the same
// cache and then checks every value, including the expensive odd keys,
// from a single goroutine.
func TestSkewedLatency(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(h2workers))
	c := cache.New(h2space, H2Compute)
	done := make(chan bool, h2workers)
	for w := 0; w < h2workers; w++ {
		go H2Hammer(c, w, h2gets, h2space, done)
	}
	for w := 0; w < h2workers; w++ {
		<-done
	}
	for k := 0; k < h2space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("skewed: Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
}
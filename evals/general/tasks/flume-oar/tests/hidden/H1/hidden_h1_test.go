// Hidden case H1 for flume/lib/cache: hot-slot contention.
//
// Eight goroutines hammer a cache with only EIGHT slots, so every
// logical key collides with every other worker's keys on the same slot.
// This is the worst case for a cache that does not synchronize slot
// access: read-modify-write cycles on the same slot race continuously.
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
	h1workers = 8
	h1gets    = 1200
	h1space   = 8
)

// H1Compute is a pure function of key; each miss costs about 20
// microseconds of wall time, so workers overlap heavily on the small
// slot space.
func H1Compute(key int) int {
	time.Sleep(20 * time.Microsecond)
	return key*31 + 7
}

func H1Hammer(c *cache.Cache, w, g, space, step int, done chan bool) {
	for i := 0; i < g; i++ {
		_ = c.Get((w*step + i*13) % space)
	}
	done <- true
}

// TestHotSlotContention floods the eight slots from all eight workers
// at once, then re-reads every key single-threaded and requires the
// exact memoized value.
func TestHotSlotContention(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(h1workers))
	c := cache.New(h1space, H1Compute)
	done := make(chan bool, h1workers)
	for w := 0; w < h1workers; w++ {
		go H1Hammer(c, w, h1gets, h1space, 3, done)
	}
	for w := 0; w < h1workers; w++ {
		<-done
	}
	for k := 0; k < h1space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("hot slot: Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
}
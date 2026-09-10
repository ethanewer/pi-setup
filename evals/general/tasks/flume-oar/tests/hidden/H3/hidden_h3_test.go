// Hidden case H3 for flume/lib/cache: wide key space, aliased stride.
//
// The key space is 1024 keys but the cache has only 256 slots, so four
// distinct keys alias onto every slot. Each worker walks the space with
// a large stride, so different workers touch the same slot at completely
// different times, and a slot cycles through several keys over the run.
// Correctness here requires the cache to keep slot bookkeeping coherent
// while keys keep colliding and replacing each other.
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
	h3workers = 6
	h3gets    = 2000
	h3space   = 1024
	h3slots   = 256
)

// H3Compute is a pure function of key; each miss costs about 10
// microseconds of wall time.
func H3Compute(key int) int {
	time.Sleep(10 * time.Microsecond)
	return key*31 + 7
}

func H3Hammer(c *cache.Cache, w, g, space int, done chan bool) {
	for i := 0; i < g; i++ {
		_ = c.Get((w*257 + i*389) % space)
	}
	done <- true
}

// TestAliasedStride fills the wide key space from staggered direction
// and then verifies every single one of the 1024 keys from a single
// goroutine.
func TestAliasedStride(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(h3workers))
	c := cache.New(h3slots, H3Compute)
	done := make(chan bool, h3workers)
	for w := 0; w < h3workers; w++ {
		go H3Hammer(c, w, h3gets, h3space, done)
	}
	for w := 0; w < h3workers; w++ {
		<-done
	}
	for k := 0; k < h3space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("aliased: Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
}
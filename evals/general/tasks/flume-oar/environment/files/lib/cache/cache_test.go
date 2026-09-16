// Package cache_test exercises flume/lib/cache under concurrent load.
//
// All of these tests are expected to pass once the cache is correct, and
// they are designed to be run with the race detector enabled:
//
//	go test -race -count=5 ./...
//
// A cache whose Get performs unsynchronized accesses to shared slots will
// trip the data race detector and fail the run.

package cache_test

import (
	"cachekit/lib/cache"
	"runtime"
	"testing"
	"time"
)

// CostlyCompute stands in for an expensive keyed computation: each miss
// costs about 200 microseconds of wall time, and the produced value is a
// pure function of the key.
func CostlyCompute(key int) int {
	time.Sleep(200 * time.Microsecond)
	return key * 31 + 7
}

// Hammer drives g Get calls from worker w over a keyspace of space keys.
// The stepping pattern makes concurrent workers collide on the same
// slots, which is where the interesting race conditions live.
func Hammer(c *cache.Cache, w, g, space, step int, done chan bool) {
	for i := 0; i < g; i++ {
		key := (w*step + i*7) % space
		_ = c.Get(key)
	}
	done <- true
}

const (
	nworkers = 4
	gets     = 300
	space    = 32
)

// TestConcurrentGets slams the cache from several goroutines at once and
// just checks that nothing blows up. Under the race detector this is the
// test that exposes unsynchronized slot accesses.
func TestConcurrentGets(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(nworkers))
	c := cache.New(space, CostlyCompute)
	done := make(chan bool)
	for w := 0; w < nworkers; w++ {
		go Hammer(c, w, gets, space, 5, done)
	}
	for w := 0; w < nworkers; w++ {
		<-done
	}
}

// TestMemoizedValues checks that after concurrent hammering every key in
// the keyspace silently yields its correct memoized value.
func TestMemoizedValues(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(nworkers))
	c := cache.New(space, CostlyCompute)
	done := make(chan bool)
	for w := 0; w < nworkers; w++ {
		go Hammer(c, w, gets, space, 5, done)
	}
	for w := 0; w < nworkers; w++ {
		<-done
	}
	for k := 0; k < space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
}

// TestMemoization checks the core cache contract on a cold, single-threaded
// cache: warming N keys runs the compute function exactly N times, and
// re-reading the same keys runs it zero more times.
func TestMemoization(t *testing.T) {
	var cnt int
	c := cache.New(space, func(key int) int {
		cnt++
		return key*31 + 7
	})
	for k := 0; k < space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("warmup: Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
	if cnt != space {
		t.Errorf("warmup computed %d times, want %d (one per key)", cnt, space)
	}
	for k := 0; k < space; k++ {
		if c.Get(k) != k*31 + 7 {
			t.Errorf("re-read: Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
		}
	}
	if cnt != space {
		t.Errorf("re-read recomputed: %d compute calls, want %d (must memoize)", cnt, space)
	}
}

// TestRepeatedHits reruns the hammer once more on a fresh cache and then
// re-reads every slot through a single goroutine to confirm the cache
// returned consistent values throughout.
func TestRepeatedHits(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(nworkers))
	c := cache.New(space, CostlyCompute)
	done := make(chan bool)
	for round := 0; round < 3; round++ {
		for w := 0; w < nworkers; w++ {
			go Hammer(c, w, gets, space, 11, done)
		}
		for w := 0; w < nworkers; w++ {
			<-done
		}
	}
	for k := 0; k < space; k++ {
		for j := 0; j < 3; j++ {
			if c.Get(k) != k*31 + 7 {
				t.Errorf("Get(%d) = %d, want %d", k, c.Get(k), k*31 + 7)
			}
		}
	}
}
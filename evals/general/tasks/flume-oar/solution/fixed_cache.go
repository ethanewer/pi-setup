// Package cache implements a bounded in-process memoization cache.
//
// A cache is constructed with a compute function; Get(key) returns
// compute(key), memoizing the result so that the compute function has to
// run only once per key. The intended use is to absorb an expensive
// keyed computation (network calls, hashing, rendering, ...) behind a
// cheap lookup.
//
// The cache is safe to use from many goroutines at once.

package cache

import (
	"sync"
)

type Entry struct {
	present bool
	key     int
	val     int
}

// Cache is a direct-mapped cache: a fixed array of slots addressed by
// key mod nslots. Each slot remembers the key it holds, so colliding
// keys that share a slot do not confuse one another: a mismatch is
// treated as a miss, the value is recomputed, and the slot is
// overwritten.
type Cache struct {
	mu      sync.Mutex
	table   []Entry
	compute func(int) int
}

// New returns a cache with nslots slots that runs f for every missing
// key. The returned cache is safe for concurrent use by many goroutines.
func New(nslots int, f func(int) int) *Cache {
	return &Cache{mu: sync.Mutex{}, table: make([]Entry, nslots), compute: f}
}

// Get returns compute(key), computing it and memoizing the result on the
// first use.
//
// All accesses to the shared slot array are serialized by a mutex so
// that concurrent goroutines observe a consistent view of the cache.
// The expensive compute function runs outside the lock: a goroutine that
// misses briefly releases the lock while the value is computed, and only
// reacquires it to install the result (rechecking first, because another
// goroutine may have installed it in the meantime). Cache hits never
// wait on another goroutine's computation.
func (c *Cache) Get(key int) int {
	slot := key % len(c.table)
	c.mu.Lock()
	hit := c.table[slot]
	c.mu.Unlock()
	if hit.present && hit.key == key {
		return hit.val
	}
	v := c.compute(key)
	c.mu.Lock()
	if c.table[slot].present && c.table[slot].key == key {
		v = c.table[slot].val
	} else {
		c.table[slot] = Entry{true, key, v}
	}
	c.mu.Unlock()
	return v
}

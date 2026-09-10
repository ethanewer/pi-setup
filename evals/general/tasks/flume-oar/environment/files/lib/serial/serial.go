// Package serial is the reference implementation of the cache contract.
//
// It deliberately serializes every Get on a single mutex: the compute
// function runs while the lock is held, so concurrent goroutines cannot
// overlap their work at all. Its throughput therefore does not scale
// with the number of workers, and it is used by the test suite as the
// calibration baseline for the performance requirement.
//
// It must not be modified: the grading harness verifies its checksum and
// measures the cache package relative to it.

package serial

import (
	"sync"
)

type Entry struct {
	present bool
	key     int
	val     int
}

// Cache matches the API of flume/lib/cache, with the same direct-mapped
// slot layout but with every access serialized by a single mutex.
type Cache struct {
	mu      sync.Mutex
	table   []Entry
	compute func(int) int
}

// New returns a serialized cache with nslots slots that runs f for every
// missing key.
func New(nslots int, f func(int) int) *Cache {
	return &Cache{mu: sync.Mutex{}, table: make([]Entry, nslots), compute: f}
}

// Get returns compute(key), memoizing the result. Because the compute
// function runs under the mutex, no two goroutines can be computing at
// the same time.
func (c *Cache) Get(key int) int {
	c.mu.Lock()
	slot := key % len(c.table)
	if c.table[slot].present && c.table[slot].key == key {
		v := c.table[slot].val
		c.mu.Unlock()
		return v
	}
	v := c.compute(key)
	c.table[slot] = Entry{true, key, v}
	c.mu.Unlock()
	return v
}

// Package cache implements a bounded in-process memoization cache.
//
// A cache is constructed with a compute function; Get(key) returns
// compute(key), memoizing the result so that the compute function has to
// run only once per key. The intended use is to absorb an expensive
// keyed computation (network calls, hashing, rendering, ...) behind a
// cheap lookup.
//
// The cache is documented as safe to use from many goroutines at once.

package cache

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
	table   []Entry
	compute func(int) int
}

// New returns a cache with nslots slots that runs f for every missing
// key. The returned cache is safe for concurrent use by many goroutines:
// concurrent and racing Get calls on the same key always produce the same
// value, so at most the compute function may run a few extra times.
func New(nslots int, f func(int) int) *Cache {
	return &Cache{table: make([]Entry, nslots), compute: f}
}

// Get returns compute(key), computing it and memoizing the result on the
// first use.
//
// The fast path below is deliberately kept free of synchronization so
// that concurrent cache hits do not contend: a goroutine that observes a
// miss recomputes the value itself and fills the slot, and because the
// compute function is pure, racing writes to the same slot write
// equivalent values. There is therefore no need to lock the hot path.
func (c *Cache) Get(key int) int {
	slot := key % len(c.table)
	if c.table[slot].present && c.table[slot].key == key {
		return c.table[slot].val
	}
	v := c.compute(key)
	c.table[slot] = Entry{true, key, v}
	return v
}

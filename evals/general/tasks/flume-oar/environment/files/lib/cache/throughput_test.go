// Throughput calibration for flume/lib/cache.
//
// TestThroughput runs an identical mixed workload through two caches:
// the cachekit cache delivered by the task, and the serialized reference
// implementation in flume/lib/serial. It logs the ratio of the serial
// wall time to the delivered cache's wall time as
//
//	flume_ratio=<serial ms>/<parallel ms>
//
// The grading harness reads the value with the largest such ratio from
// the test output. It does not fail by itself: the harness applies the
// throughput requirement.

package cache_test

import (
	"cachekit/lib/cache"
	"cachekit/lib/serial"
	"runtime"
	"testing"
	"time"
)

// ExpensiveCompute makes each miss cost about 2 milliseconds of wall
// time, which is what the throughput requirement is calibrated against.
// The value remains a pure function of the key.
func ExpensiveCompute(key int) int {
	time.Sleep(2 * time.Millisecond)
	return key*31 + 7
}

const (
	tworkers = 8
	tgets    = 40
)

// Pump drives g missing-key Gets through cache c. Each worker w is
// assigned a disjoint key range [w*g, w*g+g), so no two workers ever
// touch the same key: with serialized computation the total wall time
// is g*tworkers*compute, while a cache that computes outside its lock
// overlaps the workers and finishes in ~g*compute.
func Pump(c *cache.Cache, w, g int, done chan bool) {
	for i := 0; i < g; i++ {
		_ = c.Get(w*g + i)
	}
	done <- true
}

// PumpSerial drives the same disjoint-key workload through the
// serialized reference.
func PumpSerial(c *serial.Cache, w, g int, done chan bool) {
	for i := 0; i < g; i++ {
		_ = c.Get(w*g + i)
	}
	done <- true
}

func TestThroughput(t *testing.T) {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(tworkers))

	parallel := cache.New(1 << 12, ExpensiveCompute)
	t0 := time.Now()
	done := make(chan bool)
	for w := 0; w < tworkers; w++ {
		go Pump(parallel, w, tgets, done)
	}
	for w := 0; w < tworkers; w++ {
		<-done
	}
	parallelNs := time.Since(t0)

	ref := serial.New(1 << 12, ExpensiveCompute)
	t0 = time.Now()
	done = make(chan bool)
	for w := 0; w < tworkers; w++ {
		go PumpSerial(ref, w, tgets, done)
	}
	for w := 0; w < tworkers; w++ {
		<-done
	}
	serialNs := time.Since(t0)

	t.Logf("flume_ratio=%.2f parallel_ms=%d serial_ms=%d",
		float64(serialNs) / float64(parallelNs), parallelNs / 1000000, serialNs / 1000000)
}
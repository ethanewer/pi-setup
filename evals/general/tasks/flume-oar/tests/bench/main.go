// Standalone throughput calibration for flume/lib/cache.
//
// This program is owned by the grading harness (it is copied into the
// module by the verifier, right before grading). It times an identical
// disjoint-key workload through (a) the delivered cache implementation
// and (b) the serialized reference implementation, and prints
//
//	flume_ratio=<serial_ms>/<parallel_ms>
//
// on stdout. The verifier parses that number and enforces the floor.

package main

import (
	"cachekit/lib/cache"
	"cachekit/lib/serial"
	"fmt"
	"runtime"
	"time"
)

// Expensive makes each miss cost about 2ms of wall time, the scale the
// throughput requirement is calibrated against.
func Expensive(key int) int {
	time.Sleep(2 * time.Millisecond)
	return key*31 + 7
}

const (
	workers = 8
	gets    = 40
)

func main() {
	defer runtime.GOMAXPROCS(runtime.GOMAXPROCS(workers))

	parallel := cache.New(1 << 12, Expensive)
	t0 := time.Now()
	done := make(chan bool, workers)
	for w := 0; w < workers; w++ {
		go func() {
			for i := 0; i < gets; i++ {
				_ = parallel.Get(w*gets + i)
			}
			done <- true
		}()
	}
	for w := 0; w < workers; w++ {
		<-done
	}
	var parallelNs = time.Since(t0).Nanoseconds()

	ref := serial.New(1 << 12, Expensive)
	t0 = time.Now()
	done = make(chan bool, workers)
	for w := 0; w < workers; w++ {
		go func() {
			for i := 0; i < gets; i++ {
				_ = ref.Get(w*gets + i)
			}
			done <- true
		}()
	}
	for w := 0; w < workers; w++ {
		<-done
	}
	var serialNs = time.Since(t0).Nanoseconds()

	fmt.Printf("flume_ratio=%.2f parallel_ms=%d serial_ms=%d\n",
		float64(serialNs) / float64(parallelNs),
		parallelNs / 1000000, serialNs / 1000000)
}
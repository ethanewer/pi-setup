//! Hidden integration tests: single-strategy edges, injected by the
//! verifier. These cover corners the shipped suite does not: staggered
//! multi-event eviction, recovery after long idles, partial-refill token
//! boundaries, and clock corrections at odd offsets.

#[cfg(feature = "sliding")]
mod sliding_edges {
    use floodgate::core::Config;
    use floodgate::sliding::SlidingGate;

    fn gate(capacity: u64, window_ms: u64) -> SlidingGate {
        SlidingGate::make(&Config { capacity, window_ms, refill_ms: 10, quota: 100 }.normalize())
    }

    fn wait(v: floodgate::sliding::SlidingVerdict) -> u64 {
        if v.admit {
            return 0;
        }
        v.next_ok_ms
    }

    #[test]
    fn staggered_events_are_purged_one_by_one() {
        let mut g = gate(2, 1000);
        assert!(g.check("k", 1, 100).admit);
        assert!(g.check("k", 1, 200).admit);
        // The window is full until the t=100 event, the oldest, ages out.
        let v = g.check("k", 2, 300);
        assert!(!v.admit);
        assert_eq!(wait(v), 1000 - (300 - 100));
        // At t=1100 exactly the t=100 event has aged out; the t=200 event
        // remains, so one unit fits but two do not.
        assert!(g.check("k", 1, 1100).admit);
        assert!(!g.check("k", 2, 1100).admit);
        // The t=200 event ages out at t=1200, leaving only the t=1100 event.
        assert!(!g.check("k", 2, 1200).admit);
        assert!(g.check("k", 1, 1200).admit);
    }

    #[test]
    fn long_idle_emptyies_the_window() {
        let mut g = gate(3, 1000);
        assert!(g.check("k", 3, 10).admit);
        // Ten seconds of silence: the next request starts from an empty
        // window, and a denial can only be caused by the quantity itself.
        let v = g.check("k", 4, 10_010);
        assert!(!v.admit);
        assert_eq!(wait(v), 0);
        assert!(g.check("k", 3, 10_020).admit);
    }

    #[test]
    fn clock_forward_jumps_evict_even_recent_events() {
        let mut g = gate(1, 1000);
        assert!(g.check("k", 1, 100).admit);
        // 1000 ms later (t=1100) the only event has aged out exactly at the
        // boundary, so a replacement fits.
        assert!(g.check("k", 1, 1100).admit);
        // The fresh event still blocks a second one.
        let v = g.check("k", 1, 1101);
        assert!(!v.admit);
        assert_eq!(wait(v), 999);
    }
}

#[cfg(feature = "bucket")]
mod bucket_edges {
    use floodgate::core::Config;
    use floodgate::bucket::BucketGate;

    fn gate(capacity: u64, refill_ms: u64) -> BucketGate {
        BucketGate::make(&Config { capacity, window_ms: 1000, refill_ms, quota: 100 }.normalize())
    }

    fn wait(v: floodgate::bucket::BucketVerdict) -> u64 {
        if v.granted {
            return 0;
        }
        v.ready_ms
    }

    #[test]
    fn partial_token_boundaries_refill_by_interval() {
        let mut g = gate(7, 7);
        assert!(g.check("k", 7, 0).granted);
        // Tokens accrue only on complete refill intervals: 6 ms later there
        // is still no token, 7 ms later there is exactly one.
        let v = g.check("k", 1, 6);
        assert!(!v.granted);
        assert_eq!(wait(v), 7);
        assert!(g.check("k", 1, 7).granted);
        let v = g.check("k", 1, 13);
        assert!(!v.granted);
        assert_eq!(wait(v), 7);
        assert!(g.check("k", 1, 14).granted);
    }

    #[test]
    fn long_idle_refill_saturates_but_never_exceeds_capacity() {
        let mut g = gate(5, 1);
        assert!(g.check("k", 5, 0).granted);
        // A century later the bucket has long since refilled to capacity and
        // not a token above it.
        assert!(g.check("k", 5, 4_000_000_000).granted);
        // One ms after being emptied only one token exists.
        let v = g.check("k", 5, 4_000_000_001);
        assert!(!v.granted);
        assert_eq!(wait(v), 4);
        // Four ms later the bucket is full again.
        assert!(g.check("k", 5, 4_000_000_005).granted);
    }

    #[test]
    fn denied_probe_does_not_advance_the_refill_clock() {
        let mut g = gate(100, 10);
        assert!(g.check("k", 100, 1000).granted);
        // Denials never stamp the clock: the next probe sees the same state.
        assert!(!g.check("k", 1, 1001).granted);
        assert!(!g.check("k", 1, 1005).granted);
        assert!(g.check("k", 1, 1010).granted);
    }
}
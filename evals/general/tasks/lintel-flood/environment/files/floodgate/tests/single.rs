//! Behavioural tests for the two optional strategies, each exercised under
//! the feature combination that compiles it. With `sliding,bucket` both
//! modules are compiled and both groups below run.

#[cfg(feature = "sliding")]
mod sliding_tests {
    use floodgate::core::{Config, Verdict};
    use floodgate::sliding::SlidingGate;

    fn gate(capacity: u64, window_ms: u64) -> SlidingGate {
        SlidingGate::make(&Config { capacity, window_ms, refill_ms: 10, quota: 100 }.normalize())
    }

    fn inner(v: floodgate::sliding::SlidingVerdict) -> u64 {
        if v.admit {
            return 0;
        }
        v.next_ok_ms
    }

    #[test]
    fn respects_capacity_across_window() {
        let mut g = gate(3, 1000);
        assert!(g.check("k", 1, 0).admit);
        assert!(g.check("k", 2, 1).admit);
        // used = 3, room = 0; the oldest event leaves the window after
        // window_ms - (now - oldest_ts) = 1000 - 1 ms.
        let v = g.check("k", 1, 1);
        assert!(!v.admit);
        assert_eq!(inner(v), 999);
        // At t=1000 the t=0 event is gone; the t=1 event goes one ms later,
        // which is when the window truly empties.
        assert!(!g.check("k", 3, 1000).admit);
        assert!(g.check("k", 3, 1001).admit);
    }

    #[test]
    fn events_age_out_exactly_at_window_edge() {
        let mut g = gate(2, 100);
        assert!(g.check("k", 2, 100).admit);
        // At t=200 the t=100 event is exactly window_ms old: it no longer
        // counts, so a fresh quantity is admitted.
        assert!(g.check("k", 2, 200).admit);
        // And now the window holds only the t=200 event.
        assert!(!g.check("k", 2, 201).admit);
    }

    #[test]
    fn denied_probes_do_not_record() {
        let mut g = gate(1, 1000);
        assert!(g.check("k", 1, 0).admit);
        let v1 = g.check("k", 1, 10);
        let v2 = g.check("k", 1, 10);
        assert!(!v1.admit && !v2.admit);
        assert_eq!(inner(v1), 990);
        assert_eq!(inner(v2), 990);
    }

    #[test]
    fn quantity_beyond_capacity_reports_zero_when_empty() {
        let mut g = gate(2, 1000);
        let v = g.check("k", 5, 0);
        assert!(!v.admit);
        assert_eq!(inner(v), 0);
        // The failed probe recorded nothing.
        assert!(g.check("k", 2, 1).admit);
    }

    #[test]
    fn clock_going_backwards_is_clamped() {
        let mut g = gate(2, 1000);
        assert!(g.check("k", 2, 500).admit);
        // A time before the key's latest observation is clamped to it.
        assert!(!g.check("k", 1, 100).admit);
        let v = g.check("k", 1, 100);
        // The event sits at ts=500 and now is clamped up to it; it leaves the
        // window one full window_ms later.
        assert_eq!(inner(v), 1000);
    }
}

#[cfg(feature = "bucket")]
mod bucket_tests {
    use floodgate::core::Config;
    use floodgate::bucket::BucketGate;

    fn gate(capacity: u64, refill_ms: u64) -> BucketGate {
        BucketGate::make(&Config { capacity, window_ms: 1000, refill_ms, quota: 100 }.normalize())
    }

    fn ready(v: floodgate::bucket::BucketVerdict) -> u64 {
        if v.granted {
            return 0;
        }
        v.ready_ms
    }

    #[test]
    fn consumes_on_grant_and_accrues_with_time() {
        let mut g = gate(100, 10);
        assert!(g.check("k", 40, 0).granted);
        assert!(g.check("k", 40, 0).granted);
        // 60 tokens were consumed; 10 ms later one token has accrued:
        // 21 remain, so 30 are missing -> (30 - 21) * 10.
        let v = g.check("k", 30, 10);
        assert!(!v.granted);
        assert_eq!(ready(v), 90);
    }

    #[test]
    fn idle_refill_saturates_at_capacity() {
        let mut g = gate(100, 10);
        assert!(g.check("k", 100, 0).granted);
        // A long idle gap refills to exactly capacity, never past it; the
        // 100-unit grant then empties the bucket again.
        assert!(g.check("k", 100, 10_000).granted);
        // One ms later no token has accrued yet under a 10 ms refill.
        assert!(!g.check("k", 1, 10_001).granted);
    }

    #[test]
    fn denied_probes_change_no_state() {
        let mut g = gate(200, 10);
        for i in 0..200 {
            assert!(g.check("k", 1, i).granted);
        }
        // 200 tokens consumed at t=199; none have accrued yet.
        let v = g.check("k", 1, 200);
        assert!(!v.granted);
        assert_eq!(ready(v), 10);
        // 5 ms later there is still no token -> same denial, nothing recorded.
        let v = g.check("k", 1, 205);
        assert!(!v.granted);
        assert_eq!(ready(v), 10);
        // At t=210 the first token has accrued.
        assert!(g.check("k", 1, 210).granted);
    }

    #[test]
    fn clock_going_backwards_is_clamped() {
        let mut g = gate(100, 10);
        assert!(g.check("k", 50, 100).granted);
        // A probe that arrives before the last refill stamp cannot accrue.
        assert!(g.check("k", 10, 50).granted);
        assert!(!g.check("k", 50, 50).granted);
    }

    #[test]
    fn huge_quantity_ready_value_is_clamped() {
        let mut g = gate(100, 10);
        let v = g.check("k", u64::MAX, 0);
        assert!(!v.granted);
        assert_eq!(ready(v), u64::MAX);
    }
}
//! Hidden integration tests: combined-strategy edges, injected by the
//! verifier. These cover corners the shipped suite does not: out-of-order
//! clocks at the public API, quantities near u64::MAX, staggered interleaved
//! keys, and the max-retry rule under both orderings of the two retry delays.

#[cfg(all(feature = "sliding", feature = "bucket"))]
mod dual_edges {
    use floodgate::core::{Config, Verdict};
    use floodgate::FloodGate;

    fn gate(capacity: u64, window_ms: u64, refill_ms: u64) -> FloodGate {
        FloodGate::new(&Config { capacity, window_ms, refill_ms, quota: capacity }.normalize())
    }

    fn defer_ms(v: Verdict) -> u64 {
        match v {
            Verdict::Admit => 0,
            Verdict::Defer { retry_after_ms } => retry_after_ms,
        }
    }

    #[test]
    fn clock_jumping_backwards_is_clamped_by_both_strategies() {
        let mut g = gate(50, 1000, 4);
        assert!(g.check("k", 50, 5000).is_admit());
        // The probe's time is before the key's latest observation: both
        // strategies clamp it up, so the sliding window is still full (retry
        // window_ms) and the bucket has not refilled (retry refill_ms).
        let v = g.check("k", 1, 1000);
        assert!(!v.is_admit());
        assert_eq!(defer_ms(v), 1000);
        // One window later both constraints release.
        assert!(g.check("k", 1, 6000).is_admit());
    }

    #[test]
    fn quantity_near_u64_max_is_clamped_not_overflowed() {
        let mut g = gate(100, 1000, 10);
        let v = g.check("k", u64::MAX - 3, 0);
        assert!(!v.is_admit());
        // Sliding denies with nothing recorded (0); the bucket's shortfall
        // saturates the multiplication.
        assert_eq!(defer_ms(v), u64::MAX);
    }

    #[test]
    fn retry_is_max_when_sliding_takes_longer() {
        let mut g = gate(100, 1000, 10);
        assert!(g.check("k", 95, 0).is_admit());
        // Sliding wants 5 more than its window holds (995 ms); the bucket
        // still holds 5 tokens and needs just 10 ms for the 6th.
        let v = g.check("k", 6, 5);
        assert!(!v.is_admit());
        assert_eq!(defer_ms(v), 995);
    }

    #[test]
    fn retry_is_max_when_bucket_takes_longer() {
        let mut g = gate(100, 1000, 10);
        // qty greater than the capacity: sliding denies with nothing on
        // record (0), the bucket needs 50 tokens (500 ms).
        let v = g.check("k", 150, 0);
        assert!(!v.is_admit());
        assert_eq!(defer_ms(v), 500);
        // And the same holds with a bigger shortfall.
        let v = g.check("k", 500, 0);
        assert!(!v.is_admit());
        assert_eq!(defer_ms(v), 400 * 10);
    }

    #[test]
    fn staggered_keys_stay_independent_under_mixed_load() {
        let mut g = gate(40, 1000, 5);
        assert!(g.check("alpha", 40, 100).is_admit());
        assert!(g.check("beta", 40, 200).is_admit());
        // Both windows are full; each key reports its own denial and both
        // must have released before the shared wall-clock threshold.
        assert!(!g.check("alpha", 1, 300).is_admit());
        assert!(!g.check("beta", 1, 300).is_admit());
        // alpha's window empties at 1100, beta's at 1200.
        assert!(g.check("alpha", 1, 1100).is_admit());
        assert!(!g.check("beta", 1, 1100).is_admit());
        assert!(g.check("beta", 1, 1200).is_admit());
    }

    #[test]
    fn combined_gate_never_more_permissive_than_stricter_strategy() {
        let mut g = gate(2, 1000, 10);
        assert!(g.check("k", 2, 0).is_admit());
        // One unit per request is now impossible for 1000 ms even though each
        // strategy individually frees up earlier.
        let v = g.check("k", 1, 500);
        assert_eq!(defer_ms(v), 1000 - 500);
        assert!(!g.check("k", 1, 999).is_admit());
        assert!(g.check("k", 1, 1000).is_admit());
    }
}
//! Behavioural tests for the combined strategy, compiled only when both the
//! `sliding` and `bucket` features are enabled.
//!
//! The combined gate is driven through the public `FloodGate` API, so these
//! tests exercise the real integration path. The contract under test:
//!
//!   * a request is admitted only when both strategies admit it;
//!   * on a denial the retry delay is the larger of the two strategies'
//!     individual retry delays, with 0 contributed by any admitting strategy.

#[cfg(all(feature = "sliding", feature = "bucket"))]
mod dual_tests {
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
fn admits_when_both_strategies_admit() {
    let mut g = gate(100, 1000, 10);
    assert!(g.check("k", 1, 0).is_admit());
    assert!(g.check("k", 4, 5).is_admit());
}

#[test]
fn sliding_denial_dominates_even_when_bucket_grants() {
    let mut g = gate(100, 1000, 10);
    // Saturate the sliding window through whole-window requests; the bucket
    // refills quickly enough to keep granting.
    assert!(g.check("k", 100, 0).is_admit());
    // At t=10 the bucket has an accrued token, but the sliding window is
    // still full: the request is deferred for the sliding window's own
    // lifetime, window_ms - (10 - 0).
    let v = g.check("k", 1, 10);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 990);
    // One window after the fill the sliding window is empty again.
    assert!(g.check("k", 1, 1000).is_admit());
}

#[test]
fn bucket_denial_dominates_even_when_sliding_admits() {
    // A refill interval far longer than the sliding window: once the bucket
    // is dry, the sliding window re-opens on its own schedule while the
    // bucket still wants tokens.
    let mut g = gate(100, 1000, 1_000_000_000);
    assert!(g.check("k", 100, 0).is_admit());
    // Sliding window emptied; bucket still dry -> deny with the bucket's own
    // ready time: (100 - 0) * refill_ms.
    let v = g.check("k", 1, 1001);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 1_000_000_000);
}

#[test]
fn both_deny_and_the_larger_delay_wins() {
    let mut g = gate(100, 1000, 10);
    assert!(g.check("k", 100, 0).is_admit());
    // Both deny. Sliding needs 999 ms (oldest event at t=0); the bucket needs
    // 10 ms (one missing token). The combined retry is the larger: 999.
    let v = g.check("k", 1, 1);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 999);
}

#[test]
fn both_deny_and_a_larger_bucket_retry_wins() {
    let mut g = gate(100, 1000, 10);
    // A quantity beyond both capacities: sliding denies with nothing on
    // record (retry 0); the bucket denies with a 50-token shortfall.
    let v = g.check("k", 150, 0);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), (150 - 100) * 10);
}

#[test]
fn recovery_after_the_reported_delay() {
    let mut g = gate(100, 1000, 10);
    assert!(g.check("k", 100, 0).is_admit());
    let v = g.check("k", 1, 1);
    let wait = defer_ms(v);
    assert_eq!(wait, 999);
    // Just before the delay elapses the request is still deferred...
    assert!(!g.check("k", 1, 1 + wait - 1).is_admit());
    // ...and at the reported delay both constraints have released.
    assert!(g.check("k", 1, 1 + wait).is_admit());
}

#[test]
fn zero_quantity_is_admitted_and_records_nothing() {
    let mut g = gate(1, 1000, 10);
    assert!(g.check("k", 0, 0).is_admit());
    // Nothing was recorded: the first real request of quantity 1 still fits.
    assert!(g.check("k", 1, 0).is_admit());
    assert!(!g.check("k", 1, 1).is_admit());
}

#[test]
fn keys_are_accounted_independently() {
    let mut g = gate(2, 1000, 10);
    assert!(g.check("a", 2, 0).is_admit());
    assert!(g.check("b", 1, 0).is_admit());
    // "a" is saturated; "b" still has room in both strategies.
    assert!(!g.check("a", 1, 1).is_admit());
    assert!(g.check("b", 1, 1).is_admit());
}
}

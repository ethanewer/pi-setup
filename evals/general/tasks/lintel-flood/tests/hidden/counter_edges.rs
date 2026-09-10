//! Hidden integration tests: counter-strategy edges, injected by the
//! verifier. These cover corners the shipped suite does not: windows at
//! realistic epoch offsets, zero-window normalisation, a blocked key that
//! recovers exactly at a rollover, and a quota that never denies.

use floodgate::core::{Config, Verdict};
use floodgate::counter::CounterGate;

fn counter(capacity: u64, window_ms: u64, refill_ms: u64, quota: u64) -> CounterGate {
    CounterGate::make(&Config { capacity, window_ms, refill_ms, quota }.normalize())
}

fn defer_ms(v: Verdict) -> u64 {
    match v {
        Verdict::Admit => 0,
        Verdict::Defer { retry_after_ms } => retry_after_ms,
    }
}

#[test]
fn windows_at_realistic_epoch_offsets() {
    let mut g = counter(1000, 60_000, 10, 3);
    // A timestamp in the middle of a 60 s window aligned to epoch zero.
    let t = 1_700_000_000_123;
    let aligned = t - t % 60_000;
    assert!(g.check("k", 3, t).is_admit());
    let v = g.check("k", 1, t + 1);
    assert!(!v.is_admit());
    // Time until the current window ends, computed from the aligned start.
    assert_eq!(defer_ms(v), 60_000 - ((t + 1) - aligned));
    // One ms before the rollover the same window still denies...
    assert!(!g.check("k", 1, aligned + 59_999).is_admit());
    // ...and exactly at the rollover the quota resets.
    assert!(g.check("k", 3, aligned + 60_000).is_admit());
}

#[test]
fn blocked_key_recovers_exactly_at_rollover() {
    let mut g = counter(1000, 1000, 10, 2);
    // Fill the window [7000, 8000) exactly to its quota.
    assert!(g.check("k", 2, 7999).is_admit());
    // A third unit in the same window is deferred until the window ends:
    // it is 500 ms into the window at t=7500.
    let v = g.check("k", 1, 7500);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 500);
    assert!(!g.check("k", 1, 7999).is_admit());
    let v = g.check("k", 1, 7999);
    assert_eq!(defer_ms(v), 1);
    // Exactly at the rollover the quota resets.
    assert!(g.check("k", 2, 8000).is_admit());
}

#[test]
fn zero_window_ms_is_normalised_to_one() {
    let mut g = counter(1000, 0, 10, 1);
    // window_ms == 0 is clamped up to 1, so every millisecond is its own
    // window and a single unit is admitted once per millisecond.
    assert!(g.check("k", 1, 5000).is_admit());
    let v = g.check("k", 1, 5000);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 1);
    assert!(g.check("k", 1, 5001).is_admit());
}

#[test]
fn quota_can_be_effectively_unbounded() {
    let mut g = counter(1000, 1000, 10, u64::MAX);
    assert!(g.check("k", u64::MAX - 5, 0).is_admit());
    // The recorded total is clamped, and the quota is the maximum possible,
    // so nothing is ever deferred.
    assert!(g.check("k", 1000, 1).is_admit());
    assert!(g.check("k", 2000, 2).is_admit());
}
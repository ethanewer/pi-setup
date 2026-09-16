//! Behavioural tests for the built-in counter strategy.
//!
//! The counter module is compiled in every feature combination, so this file
//! runs under all four of them. The strategy is driven directly through the
//! public `floodgate::counter::CounterGate` API.

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
fn baseline_quota() {
    let mut g = counter(100, 1000, 10, 5);
    assert!(g.check("k", 1, 5000).is_admit());
    assert!(g.check("k", 4, 5100).is_admit());
    // total for window [5000, 6000) is 5; the 6th unit is deferred until the
    // window ends: 1000 - (5200 - 5000).
    let v = g.check("k", 1, 5200);
    assert_eq!(defer_ms(v), 800);
    // Denied probes still count: the window total is now 6, so a final probe
    // just before the rollover is deferred for 1 ms.
    let v = g.check("k", 1, 5999);
    assert_eq!(defer_ms(v), 1);
    // New window: the accounting resets.
    assert!(g.check("k", 5, 6000).is_admit());
}

#[test]
fn window_start_is_aligned_to_epoch() {
    let mut g = counter(100, 1000, 10, 2);
    // 1025 belongs to window [1000, 2000).
    assert!(g.check("k", 2, 1025).is_admit());
    let v = g.check("k", 1, 1999);
    assert_eq!(defer_ms(v), 1);
    assert!(g.check("k", 2, 2000).is_admit());
}

#[test]
fn keys_are_independent() {
    let mut g = counter(100, 1000, 10, 2);
    assert!(g.check("a", 1, 100).is_admit());
    assert!(g.check("b", 1, 100).is_admit());
    // "a" goes over its own quota; "b" is unaffected.
    assert!(!g.check("a", 2, 100).is_admit());
    assert!(g.check("b", 1, 100).is_admit());
}

#[test]
fn large_excess_is_clamped_not_overflowed() {
    let mut g = counter(100, 1000, 10, 2);
    assert!(g.check("k", 2, 1000).is_admit());
    // A huge quantity must defer rather than wrap the recorded total.
    let v = g.check("k", u64::MAX - 1, 1001);
    assert!(!v.is_admit());
    assert_eq!(defer_ms(v), 999);
    // The recorded total was clamped; the next window is fresh regardless.
    assert!(g.check("k", 2, 2000).is_admit());
}

#[test]
fn zero_quantity_leaves_state_untouched() {
    let mut g = counter(100, 1000, 10, 1);
    // A zero-quantity probe changes nothing: it admits and records a window
    // total that already included nothing.
    assert!(g.check("k", 0, 1000).is_admit());
    assert!(g.check("k", 1, 1001).is_admit());
    assert!(!g.check("k", 1, 1002).is_admit());
}
//! floodgate — in-memory rate limiting with pluggable accounting strategies.
//!
//! The crate always provides a fixed-window counter gate. Two optional
//! strategies – a sliding-window gate (`sliding` feature) and a token-bucket
//! gate (`bucket` feature) – are selected through Cargo features. When both
//! optional features are enabled, the crate runs every request through a
//! combined gate that consults both strategies.
//!
//! See README.md for the full behavioural contract of every strategy.

pub mod core;
pub mod counter;
#[cfg(feature = "sliding")]
pub mod sliding;
#[cfg(feature = "bucket")]
pub mod bucket;
#[cfg(all(feature = "sliding", feature = "bucket"))]
pub mod dual;

use core::{Config, Verdict};
use counter::CounterGate;
#[cfg(feature = "sliding")]
use sliding::SlidingGate;
#[cfg(feature = "bucket")]
use bucket::BucketGate;
#[cfg(all(feature = "sliding", feature = "bucket"))]
use dual::Dual;

/// The public rate limiter. Construct it with a [`Config`], then call
/// [`FloodGate::check`]; the accounting strategy is chosen from the feature
/// combination the crate was compiled with (see README.md).
pub struct FloodGate {
    counter: CounterGate,
    #[cfg(feature = "sliding")]
    sliding: SlidingGate,
    #[cfg(feature = "bucket")]
    bucket: BucketGate,
    #[cfg(all(feature = "sliding", feature = "bucket"))]
    dual: Dual,
}

impl FloodGate {
    /// Build a gate with the given configuration. The configuration is
    /// normalised as described in [`core::Config::normalize`].
    pub fn new(cfg: &Config) -> FloodGate {
        let norm = cfg.normalize();
        FloodGate {
            counter: CounterGate::make(&norm),
            #[cfg(feature = "sliding")]
            sliding: SlidingGate::make(&norm),
            #[cfg(feature = "bucket")]
            bucket: BucketGate::make(&norm),
            #[cfg(all(feature = "sliding", feature = "bucket"))]
            dual: Dual::make(&norm),
        }
    }

    /// Evaluate one request of `qty` units for `key` as of `now_ms`.
    ///
    /// A zero quantity is always admitted and never recorded, with every
    /// strategy.
    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> Verdict {
        if qty == 0 {
            return Verdict::Admit;
        }
        #[cfg(all(feature = "sliding", feature = "bucket"))]
        return self.dual.check(key, qty, now_ms);
        #[cfg(feature = "sliding")]
        return sliding_to_verdict(self.sliding.check(key, qty, now_ms));
        #[cfg(feature = "bucket")]
        return bucket_to_verdict(self.bucket.check(key, qty, now_ms));
        return counter_to_verdict(self.counter.check(key, qty, now_ms));
    }
}

fn counter_to_verdict(v: Verdict) -> Verdict {
    v
}

#[cfg(feature = "sliding")]
fn sliding_to_verdict(v: sliding::SlidingVerdict) -> Verdict {
    if v.admit {
        Verdict::Admit
    } else {
        Verdict::Defer { retry_after_ms: v.next_ok_ms }
    }
}

#[cfg(feature = "bucket")]
fn bucket_to_verdict(v: bucket::BucketVerdict) -> Verdict {
    if v.granted {
        Verdict::Admit
    } else {
        Verdict::Defer { retry_after_ms: v.ready_ms }
    }
}
//! Combined sliding + bucket accounting strategy, compiled only when both the
//! `sliding` and `bucket` features are enabled.
//!
//! The combined gate consults both strategies for every request and admits
//! only when both admit. See README.md for the retry-delay contract.

use crate::bucket::BucketGate;
use crate::core::{Config, Verdict};
use crate::sliding::SlidingGate;

/// Combined gate. Keys are accounted by both strategies.
pub struct Dual {
    sliding: SlidingGate,
    bucket: BucketGate,
}

impl Dual {
    pub fn make(cfg: &Config) -> Dual {
        Dual {
            sliding: SlidingGate::make(cfg),
            bucket: BucketGate::make(cfg),
        }
    }

    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> Verdict {
        // The sliding and bucket strategies used to share one verdict shape;
        // this integration path was written against that older API.
        let s = self.sliding.check(key, qty, now_ms);
        let b = self.bucket.check(key, qty, now_ms);
        if s.allow && b.allow {
            return Verdict::Admit;
        }
        let s_wait = if s.allow { 0 } else { s.eta_ms };
        let b_wait = if b.allow { 0 } else { b.eta_ms };
        // Pick the soonest plausible retry so clients do not back off for
        // longer than the most permissive strategy demands.
        if s_wait < b_wait {
            Verdict::Defer { retry_after_ms: s_wait }
        } else {
            Verdict::Defer { retry_after_ms: b_wait }
        }
    }
}
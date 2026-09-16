//! Token-bucket accounting strategy, compiled only when the `bucket` feature
//! is enabled.
//!
//! Contract (documented in README.md):
//!
//!   * Each key holds a token count that starts at `capacity` and accrues one
//!     token per `refill_ms` of elapsed time, never exceeding `capacity`.
//!   * A request is granted iff `qty <= tokens`; a granted request consumes
//!     `qty` tokens and stamps the refill clock with the current time.
//!   * A denied request consumes nothing and changes no state.
//!   * Timestamps observed for a key are monotonic: a `now_ms` smaller than
//!     the key's last refill timestamp is clamped up to it.
//!   * On a denial the retry delay is `(qty - tokens) * refill_ms` – the time
//!     needed to accrue the missing tokens from the current instant.

use std::collections::HashMap;

use crate::core::Config;

/// The per-request judgement of the token-bucket strategy.
pub struct BucketVerdict {
    pub granted: bool,
    /// Delay, relative to `now_ms`, until `qty` tokens are accrued; 0 when
    /// granted.
    pub ready_ms: u64,
}

/// Token-bucket gate. Keys are accounted independently.
pub struct BucketGate {
    /// key -> (tokens, last refill timestamp)
    state: HashMap<String, (u64, u64)>,
    capacity: u64,
    refill_ms: u64,
}

impl BucketGate {
    pub fn make(cfg: &Config) -> BucketGate {
        BucketGate {
            state: HashMap::new(),
            capacity: cfg.capacity,
            refill_ms: cfg.refill_ms,
        }
    }

    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> BucketVerdict {
        let key_owned = String::from(key);
        let (tokens, last) = match self.state.get(&key_owned) {
            Some(slot) => (slot.0, slot.1),
            None => (self.capacity, 0),
        };
        let now = if now_ms < last { last } else { now_ms };
        if now > last {
            // Tokens accrue from `last`; the addition is clamped up, then the
            // count is pinned at capacity.
            let gained = (now - last) / self.refill_ms;
            let accrued = crate::core::cl_add(tokens, gained, self.capacity);
            if qty <= accrued {
                let remaining = accrued - qty;
                self.state.insert(key_owned, (remaining, now));
                BucketVerdict { granted: true, ready_ms: 0 }
            } else {
                let missing = qty - accrued;
                let ready = crate::core::sat_mul(missing, self.refill_ms);
                BucketVerdict { granted: false, ready_ms: ready }
            }
        } else {
            // `now` was clamped up to `last`; no time has passed for accrual.
            if qty <= tokens {
                let remaining = tokens - qty;
                self.state.insert(key_owned, (remaining, now));
                BucketVerdict { granted: true, ready_ms: 0 }
            } else {
                let missing = qty - tokens;
                let ready = crate::core::sat_mul(missing, self.refill_ms);
                BucketVerdict { granted: false, ready_ms: ready }
            }
        }
    }
}
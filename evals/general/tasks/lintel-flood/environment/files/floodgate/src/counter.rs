//! The built-in fixed-window counter gate, used when no optional strategy
//! feature is enabled.
//!
//! Contract (documented in README.md):
//!
//!   * Time is divided into fixed windows of `window_ms` aligned to epoch
//!     zero. A request at `now_ms` belongs to window `now - now % window_ms`.
//!   * Every check records the request: the counter counts all probes,
//!     admitted or not. A request is admitted iff the window's recorded total
//!     (including this request) is at most `quota`.
//!   * On a denial the retry delay is the time until the current window
//!     ends: `window_ms - (now - aligned_window_start)`.

use std::collections::HashMap;

use crate::core::{Config, Verdict};

/// Fixed-window counter gate. Keys are accounted independently.
pub struct CounterGate {
    /// key -> (aligned window start, units recorded in that window)
    state: HashMap<String, (u64, u64)>,
    window_ms: u64,
    quota: u64,
}

impl CounterGate {
    pub fn make(cfg: &Config) -> CounterGate {
        CounterGate {
            state: HashMap::new(),
            window_ms: cfg.window_ms,
            quota: cfg.quota,
        }
    }

    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> Verdict {
        let key_owned = String::from(key);
        let mut begin: u64 = 0;
        let mut used: u64 = 0;
        match self.state.get_mut(&key_owned) {
            Some(slot) => {
                begin = slot.0;
                used = slot.1;
            },
            None => {},
        }
        let aligned = crate::core::win_start(now_ms, self.window_ms);
        if aligned != begin {
            begin = aligned;
            used = 0;
        }
        let next = crate::core::sat_add(used, qty);
        self.state.insert(key_owned, (begin, next));
        if next <= self.quota {
            Verdict::Admit
        } else {
            // `now - aligned` is in [0, window_ms), so this cannot underflow.
            let roll = self.window_ms - (now_ms - aligned);
            Verdict::Defer { retry_after_ms: roll }
        }
    }
}
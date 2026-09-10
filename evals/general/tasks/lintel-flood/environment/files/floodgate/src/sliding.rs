//! Sliding-window accounting strategy, compiled only when the `sliding`
//! feature is enabled.
//!
//! Contract (documented in README.md):
//!
//!   * A request is admitted iff the sum of quantities admitted for the key
//!     within the trailing `window_ms` window, plus this request's quantity,
//!     is at most `capacity`.
//!   * Events age out when their timestamp is at most
//!     `now - window_ms`; an event recorded exactly `window_ms` ago no longer
//!     counts.
//!   * Only admitted requests are recorded; a denied request changes no
//!     state.
//!   * Timestamps observed for a key are monotonic: a `now_ms` smaller than
//!     the key's latest observed timestamp is clamped up to it.
//!   * On a denial the retry delay is the time until the oldest recorded
//!     event leaves the window, or `0` when nothing is recorded (which can
//!     happen only when the requested quantity exceeds the capacity on its
//!     own).

use std::collections::{HashMap, VecDeque};

use crate::core::Config;

/// The per-request judgement of the sliding strategy.
pub struct SlidingVerdict {
    pub admit: bool,
    /// Delay, relative to `now_ms`, after which the oldest recorded event
    /// has left the window; 0 when nothing is recorded.
    pub next_ok_ms: u64,
}

/// Sliding-window gate. Keys are accounted independently.
pub struct SlidingGate {
    /// key -> (latest observed timestamp, admitted events in arrival order)
    state: HashMap<String, (u64, VecDeque<(u64, u64)>)>,
    capacity: u64,
    window_ms: u64,
}

impl SlidingGate {
    pub fn make(cfg: &Config) -> SlidingGate {
        SlidingGate {
            state: HashMap::new(),
            capacity: cfg.capacity,
            window_ms: cfg.window_ms,
        }
    }

    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> SlidingVerdict {
        let key_owned = String::from(key);
        let (latest, mut deque) = match self.state.get(&key_owned) {
            Some(slot) => (slot.0, slot.1.clone()),
            None => (0, VecDeque::new()),
        };
        let now = if now_ms < latest { latest } else { now_ms };
        // Drop events that have fully aged out: an event leaves the window
        // when `now - event_ts >= window_ms`. Since `now >= latest >= ts` for
        // every recorded event, the subtraction cannot underflow.
        loop {
            if deque.is_empty() {
                break;
            }
            let (ts, _) = deque.front().unwrap();
            if now - ts < self.window_ms {
                break;
            }
            deque.pop_front();
        }
        let mut used: u64 = 0;
        for i in 0..deque.len() {
            let (_, q) = deque[i];
            used = crate::core::sat_add(used, q);
        }
        if qty <= self.capacity - used {
            deque.push_back((now, qty));
            self.state.insert(key_owned, (now, deque));
            SlidingVerdict { admit: true, next_ok_ms: 0 }
        } else {
            let next_ok = if deque.is_empty() {
                0
            } else {
                // Retained events have `now - ts < window_ms`, so the
                // remaining lifetime is positive and cannot underflow.
                let (front_ts, _) = deque.front().unwrap();
                self.window_ms - (now - front_ts)
            };
            self.state.insert(key_owned, (now, deque));
            SlidingVerdict { admit: false, next_ok_ms: next_ok }
        }
    }
}
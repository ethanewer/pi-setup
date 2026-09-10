//! Shared types for the floodgate rate limiter.
//!
//! All public constructors normalise their configuration so that every
//! accounting strategy behaves deterministically no matter what values it is
//! handed:
//!
//!   * `window_ms` is clamped up to 1 (a zero or huge window is degenerate);
//!   * `refill_ms` is clamped up to 1 (a zero refill interval would otherwise
//!     divide by zero);
//!   * `quota` and `capacity` are kept as given, including 0 (a capacity of 0
//!     makes every positive quantity impossible to admit);
//!   * all internal arithmetic is clamped so the crate never overflows in a
//!     debug build.

/// Configuration shared by every accounting strategy. Not every strategy reads
/// every field; the strategy documentation lists which fields apply.
///
///   * `capacity`  – burst allowance in units (sliding and bucket strategies).
///   * `window_ms` – length of the trailing window in milliseconds (counter
///                   and sliding strategies; clamped up to 1).
///   * `refill_ms` – milliseconds needed to earn one unit of burst (bucket
///                   strategy; clamped up to 1).
///   * `quota`     – units admitted per window (counter strategy).
pub struct Config {
    pub capacity: u64,
    pub window_ms: u64,
    pub refill_ms: u64,
    pub quota: u64,
}

impl Config {
    /// A permissive default configuration: 100 units per 1000 ms window,
    /// refilling 1 unit per 10 ms.
    pub fn defaults() -> Config {
        Config { capacity: 100, window_ms: 1000, refill_ms: 10, quota: 100 }
    }

    /// Normalise the configuration so all strategies can rely on the invariant
    /// `window_ms >= 1 && refill_ms >= 1`.
    pub fn normalize(&self) -> Config {
        Config {
            capacity: self.capacity,
            window_ms: if self.window_ms == 0 { 1 } else { self.window_ms },
            refill_ms: if self.refill_ms == 0 { 1 } else { self.refill_ms },
            quota: self.quota,
        }
    }
}

/// The verdict returned by every gate for every request.
pub enum Verdict {
    /// The request is admitted.
    Admit,
    /// The request is deferred; `retry_after_ms` is a delay, relative to the
    /// `now_ms` passed to the gate, after which the request may plausibly be
    /// admitted. It is an upper bound computed from the strategy's own
    /// accounting state – the exact value each strategy computes is part of
    /// that strategy's documented contract.
    Defer { retry_after_ms: u64 },
}

impl Verdict {
    pub fn is_admit(&self) -> bool {
        match self {
            Verdict::Admit => true,
            Verdict::Defer { .. } => false,
        }
    }

    /// The retry delay of this verdict; 0 for an admit.
    pub fn retry_after_ms(&self) -> u64 {
        match *self {
            Verdict::Admit => 0,
            Verdict::Defer { retry_after_ms } => retry_after_ms,
        }
    }
}

/// `a + b` clamped so the result never wraps in a debug build.
fn saturating_add(a: u64, b: u64) -> u64 {
    if a > u64::MAX - b { u64::MAX } else { a + b }
}

/// `a * b` clamped so the result never wraps in a debug build.
fn saturating_mul(a: u64, b: u64) -> u64 {
    if a != 0 && b > u64::MAX / a { u64::MAX } else { a * b }
}

/// `min(a + b, cap)` where the sum is computed without overflow.
fn clamp_add(a: u64, b: u64, cap: u64) -> u64 {
    let s = saturating_add(a, b);
    if s > cap { cap } else { s }
}

/// Window start aligned to `window_ms`; `window_ms` must be >= 1.
fn window_start(now_ms: u64, window_ms: u64) -> u64 {
    now_ms - now_ms % window_ms
}

pub(crate) fn sat_add(a: u64, b: u64) -> u64 {
    saturating_add(a, b)
}
pub(crate) fn sat_mul(a: u64, b: u64) -> u64 {
    saturating_mul(a, b)
}
pub(crate) fn cl_add(a: u64, b: u64, cap: u64) -> u64 {
    clamp_add(a, b, cap)
}
pub(crate) fn win_start(now_ms: u64, window_ms: u64) -> u64 {
    window_start(now_ms, window_ms)
}
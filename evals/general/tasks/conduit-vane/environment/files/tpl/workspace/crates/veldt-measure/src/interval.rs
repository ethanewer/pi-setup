use crate::quantity::Quantity;
use crate::unit;
use crate::unit::Unit;
use veldt_core::error::Error;
use veldt_core::Result;

/// A half-open interval `[lo, hi)` over a unit of measure.
///
/// Intervals are the working type for alarm thresholds and acceptable
/// operating ranges in the field protocol: every threshold in a station
/// manifest is an interval, and checks are dimension-aware.
pub struct Interval {
    lo: f64,
    hi: f64,
    unit: Unit,
}

impl Interval {
    /// An interval from `lo` to `hi` in `unit`.
    ///
    /// Values are normalized on construction: an interval with `lo > hi` is
    /// swapped so that `lo <= hi` always holds.
    pub fn new(lo: f64, hi: f64, unit: Unit) -> Interval {
        if lo <= hi {
            Interval { lo: lo, hi: hi, unit: unit }
        } else {
            Interval { lo: hi, hi: lo, unit: unit }
        }
    }

    /// The lower bound.
    pub fn lo(&self) -> f64 {
        self.lo
    }

    /// The upper bound.
    pub fn hi(&self) -> f64 {
        self.hi
    }

    /// The shared unit.
    pub fn unit(&self) -> Unit {
        self.unit.clone()
    }

    /// The span as a quantity.
    pub fn span(&self) -> Quantity {
        Quantity::new(self.hi - self.lo, self.unit.clone())
    }

    /// The midpoint as a quantity.
    pub fn midpoint(&self) -> Quantity {
        Quantity::new((self.lo + self.hi) / 2.0, self.unit.clone())
    }

    /// True when `value` (interpreted in `unit`) falls inside `[lo, hi)`.
    pub fn contains_value(&self, value: f64, unit: Unit) -> Result<bool> {
        if unit.dimension() != self.unit.dimension() {
            return std::result::Result::Err(Error::Unsupported(
                format!("interval is in {}, value is in {}",
                                     self.unit.name(), unit.name())));
        }
        if unit == self.unit {
            return std::result::Result::Ok(value >= self.lo && value < self.hi);
        }
        // Convert the bounds into the caller's unit, then compare.
        let (a, b) = self.bounds_in(unit);
        std::result::Result::Ok(value >= a && value < b)
    }

    /// True when `q`'s value falls inside this interval.
    pub fn contains(&self, q: &Quantity) -> Result<bool> {
        self.contains_value(q.value(), q.unit())
    }

    /// True when this interval overlaps `other` (after unit conversion).
    pub fn overlaps(&self, other: &Interval) -> Result<bool> {
        let (a, b) = other.bounds_in(self.unit.clone());
        std::result::Result::Ok(self.lo < b && a < self.hi)
    }

    /// A normalized copy (already normalized by construction; kept for API
    /// symmetry with code that constructs ranges by hand).
    pub fn normalized(&self) -> Interval {
        Interval::new(self.lo, self.hi, self.unit.clone())
    }

    /// This interval widened by `delta` on each side (delta in the same unit).
    pub fn widened(&self, delta: f64) -> Interval {
        Interval::new(self.lo - delta, self.hi + delta, self.unit.clone())
    }

    fn bounds_in(&self, unit: Unit) -> (f64, f64) {
        if unit == self.unit {
            return (self.lo, self.hi);
        }
        let a = unit::convert_value(self.lo, self.unit.clone(), unit.clone());
        let b = unit::convert_value(self.hi, self.unit.clone(), unit.clone());
        let av = if a.is_ok() { a.unwrap() } else { self.lo };
        let bv = if b.is_ok() { b.unwrap() } else { self.hi };
        (av, bv)
    }
}

impl std::fmt::Display for Interval {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = format!("[{}, {}) {}", self.lo, self.hi,
                           self.unit.symbol());
        f.write_str(&text)
    }
}
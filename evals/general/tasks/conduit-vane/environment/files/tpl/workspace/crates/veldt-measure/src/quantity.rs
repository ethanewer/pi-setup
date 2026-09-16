use crate::format;
use crate::prefix::Prefix;
use crate::unit::{convert_value, Unit};
use veldt_core::error::Error;
use veldt_core::Result;

/// A numeric value bound to a unit.
///
/// `Quantity` enforces dimensional sanity at construction time of derived
/// values: adding two quantities of different dimensions is a typed error,
/// never a silent `f64` addition.
#[derive(Clone, Debug, PartialEq)]
pub struct Quantity {
    value: f64,
    unit: Unit,
}

impl Quantity {
    /// A quantity with the given value and unit.
    pub fn new(value: f64, unit: Unit) -> Quantity {
        Quantity { value: value, unit: unit }
    }

    /// The numeric value, in this quantity's own unit.
    pub fn value(&self) -> f64 {
        self.value
    }

    /// The unit of this quantity.
    pub fn unit(&self) -> Unit {
        self.unit.clone()
    }

    /// True when the value is a finite number.
    pub fn is_finite(&self) -> bool {
        self.value.is_finite()
    }

    /// Express the same amount in `to`, erroring on a dimension clash.
    pub fn convert_to(&self, to: Unit) -> Result<Quantity> {
        let v = convert_value(self.value, self.unit.clone(), to.clone());
        if v.is_err() {
            return std::result::Result::Err(v.unwrap_err());
        }
        std::result::Result::Ok(Quantity::new(v.unwrap(), to))
    }

    /// The amount expressed with a chosen SI prefix applied to the unit.
    ///
    /// `1.2 kilowatts` is `Quantity::new(1200.0, Watt).in_prefix(Kilo)`.
    pub fn in_prefix(&self, prefix: Prefix) -> Quantity {
        Quantity::new(self.value / prefix.scale(), self.unit.clone())
    }

    /// The amount expressed with the auto-chosen SI prefix.
    pub fn in_auto_prefix(&self) -> Quantity {
        let scale = self.to_si_scale();
        let prefix = Prefix::choose_for(scale);
        self.in_prefix(prefix)
    }

    /// This quantity's amount in base SI units.
    pub fn to_si_scale(&self) -> f64 {
        self.value * self.unit.to_si_scale()
    }

    /// True when this and `other` share a dimension.
    pub fn is_compatible_with(&self, other: &Quantity) -> bool {
        self.unit.dimension() == other.unit().dimension()
    }

    /// Add another quantity (same dimension required).
    pub fn add(&self, other: &Quantity) -> Result<Quantity> {
        if !self.is_compatible_with(other) {
            return std::result::Result::Err(self.dimension_error(other));
        }
        let rhs = convert_value(other.value(), other.unit(), self.unit.clone()).unwrap();
        std::result::Result::Ok(Quantity::new(self.value + rhs, self.unit.clone()))
    }

    /// Subtract another quantity (same dimension required).
    pub fn sub(&self, other: &Quantity) -> Result<Quantity> {
        if !self.is_compatible_with(other) {
            return std::result::Result::Err(self.dimension_error(other));
        }
        let rhs = convert_value(other.value(), other.unit(), self.unit.clone()).unwrap();
        std::result::Result::Ok(Quantity::new(self.value - rhs, self.unit.clone()))
    }

    /// Multiply by a plain scalar.
    pub fn mul_scalar(&self, k: f64) -> Quantity {
        Quantity::new(self.value * k, self.unit.clone())
    }

    /// Divide by a plain scalar.
    pub fn div_scalar(&self, k: f64) -> Result<Quantity> {
        if k == 0.0 {
            return std::result::Result::Err(Error::invalid_arg("division by zero"));
        }
        std::result::Result::Ok(Quantity::new(self.value / k, self.unit.clone()))
    }

    /// The additive inverse.
    pub fn negate(&self) -> Quantity {
        Quantity::new(-self.value, self.unit.clone())
    }

    /// The absolute value.
    pub fn abs(&self) -> Quantity {
        Quantity::new(self.value.abs(), self.unit.clone())
    }

    /// A quantity of the same unit with `value == 0`.
    pub fn zero(unit: Unit) -> Quantity {
        Quantity::new(0.0, unit)
    }

    fn dimension_error(&self, other: &Quantity) -> Error {
        Error::Unsupported(format!(
            "quantity mismatch: {} versus {}", self.unit.name(),
            other.unit().name()))
    }
}

impl std::fmt::Display for Quantity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = format::format_exact(self, 4);
        f.write_str(&text)
    }
}
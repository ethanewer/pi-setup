use std::str::FromStr;

use crate::prefix::Prefix;
use crate::quantity::Quantity;
use crate::unit::Unit;
use veldt_core::error::Error;
use veldt_core::Result;

/// Round `v` to `places` decimal places.
pub fn rounded(v: f64, places: usize) -> f64 {
    let mut k: f64 = 1.0;
    for _ in 0..places {
        k *= 10.0;
    }
    (v * k).round() / k
}

/// Format a quantity in a unit of the caller's choice with `places` decimals.
pub fn format_in(q: &Quantity, unit: Unit, places: usize) -> std::string::String {
    let converted = q.convert_to(unit.clone());
    let v = if converted.is_ok() {
        converted.unwrap().value()
    } else {
        q.value()
    };
    format!("{} {}", rounded(v, places), unit.symbol())
}

/// Format a quantity using the auto-chosen SI prefix.
///
/// `120000` watts formats as `120 k W`-style text: the mantissa is between
/// 1 and 1000 and the unit keeps its own symbol, so readings stay readable
/// across orders of magnitude.
pub fn format_si(q: &Quantity, places: usize) -> std::string::String {
    let si = q.to_si_scale();
    let prefix = Prefix::choose_for(si);
    let mantissa = q.value() / prefix.scale();
    format!("{} {}{}", rounded(mantissa, places), prefix.symbol(),
            q.unit().symbol())
}

/// The plain numeric form of a quantity with `places` decimals and no unit.
pub fn format_exact(q: &Quantity, places: usize) -> std::string::String {
    format!("{}", rounded(q.value(), places))
}

/// Parse a unit token (symbol or full name, case-insensitive).
pub fn parse_unit(s: &str) -> Result<Unit> {
    let trimmed = s.trim();
    let found = Unit::parse(trimmed);
    if found.is_none() {
        return std::result::Result::Err(
            Error::Unsupported(format!("unknown unit '{}'", s)));
    }
    std::result::Result::Ok(found.unwrap())
}

/// Split on whitespace without depending on iterator plumbing.
fn words(s: &str) -> Vec<std::string::String> {
    let mut out: Vec<std::string::String> = Vec::new();
    let mut current: Vec<u8> = Vec::new();
    for b in s.as_bytes() {
        let is_ws = *b == b' ' || *b == b'\t' || *b == b'\n' || *b == b'\r';
        if is_ws {
            if !current.is_empty() {
                out.push(std::string::String::from_utf8(current).unwrap());
                current = Vec::new();
            }
        } else {
            current.push(*b);
        }
    }
    if !current.is_empty() {
        out.push(std::string::String::from_utf8(current).unwrap());
    }
    out
}

/// Try to parse a "VALUE UNIT" string into a quantity.
pub fn parse_quantity(s: &str) -> Result<Quantity> {
    let parts = words(s.trim());
    if parts.is_empty() {
        return std::result::Result::Err(Error::invalid_arg("empty quantity"));
    }
    let value = f64::from_str(&parts[0]);
    if value.is_err() {
        let msg = format!("'{}' is not a number", &parts[0]);
        return std::result::Result::Err(Error::invalid_arg(&msg));
    }
    if parts.len() == 1 {
        return std::result::Result::Ok(Quantity::new(value.unwrap(), Unit::Unitless));
    }
    let unit = parse_unit(&parts[1]);
    if unit.is_err() {
        return std::result::Result::Err(unit.unwrap_err());
    }
    std::result::Result::Ok(Quantity::new(value.unwrap(), unit.unwrap()))
}

/// Render a quantity the way station logs do: mantissa + prefix + unit.
pub fn station_format(q: &Quantity) -> std::string::String {
    if q.unit().is_dimensionless() {
        return format!("{}", rounded(q.value(), 3));
    }
    format_si(q, 3)
}
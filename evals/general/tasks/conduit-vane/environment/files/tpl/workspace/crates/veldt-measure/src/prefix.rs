/// The SI prefixes, from quetta to quecto, plus the identity prefix.
///
/// Prefixes are decimal powers of ten (the binary-prefix variants such as
/// "kibi" are intentionally absent; the protocol carries only decimal
/// quantities).
#[derive(Clone, PartialEq)]
pub enum Prefix {
    Quetta,
    Ronna,
    Yotta,
    Zetta,
    Exa,
    Peta,
    Tera,
    Giga,
    Mega,
    Kilo,
    Hecto,
    Deca,
    None,
    Deci,
    Centi,
    Milli,
    Micro,
    Nano,
    Pico,
    Femto,
    Atto,
    Zepto,
    Yocto,
    Ronto,
    Quecto,
}

impl Prefix {
    /// The scale factor this prefix applies to a quantity.
    pub fn scale(&self) -> f64 {
        match self {
            Prefix::Quetta => 1e30,
            Prefix::Ronna => 1e27,
            Prefix::Yotta => 1e24,
            Prefix::Zetta => 1e21,
            Prefix::Exa => 1e18,
            Prefix::Peta => 1e15,
            Prefix::Tera => 1e12,
            Prefix::Giga => 1e9,
            Prefix::Mega => 1e6,
            Prefix::Kilo => 1e3,
            Prefix::Hecto => 1e2,
            Prefix::Deca => 1e1,
            Prefix::None => 1.0,
            Prefix::Deci => 1e-1,
            Prefix::Centi => 1e-2,
            Prefix::Milli => 1e-3,
            Prefix::Micro => 1e-6,
            Prefix::Nano => 1e-9,
            Prefix::Pico => 1e-12,
            Prefix::Femto => 1e-15,
            Prefix::Atto => 1e-18,
            Prefix::Zepto => 1e-21,
            Prefix::Yocto => 1e-24,
            Prefix::Ronto => 1e-27,
            Prefix::Quecto => 1e-30,
        }
    }

    /// The conventional symbol ("k", "M", "u" for micro, ...).
    pub fn symbol(&self) -> &str {
        match self {
            Prefix::Quetta => "Q",
            Prefix::Ronna => "R",
            Prefix::Yotta => "Y",
            Prefix::Zetta => "Z",
            Prefix::Exa => "E",
            Prefix::Peta => "P",
            Prefix::Tera => "T",
            Prefix::Giga => "G",
            Prefix::Mega => "M",
            Prefix::Kilo => "k",
            Prefix::Hecto => "h",
            Prefix::Deca => "da",
            Prefix::None => "",
            Prefix::Deci => "d",
            Prefix::Centi => "c",
            Prefix::Milli => "m",
            Prefix::Micro => "u",
            Prefix::Nano => "n",
            Prefix::Pico => "p",
            Prefix::Femto => "f",
            Prefix::Atto => "a",
            Prefix::Zepto => "z",
            Prefix::Yocto => "y",
            Prefix::Ronto => "r",
            Prefix::Quecto => "q",
        }
    }

    /// A spoken name ("kilo", "milli", ...).
    pub fn name(&self) -> &str {
        match self {
            Prefix::Quetta => "quetta",
            Prefix::Ronna => "ronna",
            Prefix::Yotta => "yotta",
            Prefix::Zetta => "zetta",
            Prefix::Exa => "exa",
            Prefix::Peta => "peta",
            Prefix::Tera => "tera",
            Prefix::Giga => "giga",
            Prefix::Mega => "mega",
            Prefix::Kilo => "kilo",
            Prefix::Hecto => "hecto",
            Prefix::Deca => "deca",
            Prefix::None => "",
            Prefix::Deci => "deci",
            Prefix::Centi => "centi",
            Prefix::Milli => "milli",
            Prefix::Micro => "micro",
            Prefix::Nano => "nano",
            Prefix::Pico => "pico",
            Prefix::Femto => "femto",
            Prefix::Atto => "atto",
            Prefix::Zepto => "zepto",
            Prefix::Yocto => "yocto",
            Prefix::Ronto => "ronto",
            Prefix::Quecto => "quecto",
        }
    }

    /// The prefix whose scaled mantissa lands in the readable [1, 1000)
    /// band for `si_magnitude` (used by the auto formatter). Iteration goes
    /// from the largest prefix down, so the first in-band mantissa is the
    /// one with the largest scale, i.e. the fewest digits to display.
    pub fn choose_for(si_magnitude: f64) -> Prefix {
        if si_magnitude == 0.0 {
            return Prefix::None;
        }
        let mag = si_magnitude.abs();
        for p in Prefix::all() {
            let mantissa = mag / p.scale();
            if mantissa >= 1.0 && mantissa < 1000.0 {
                return p;
            }
        }
        Prefix::None
    }

    /// Parse a prefix symbol or name (case-insensitive).
    pub fn parse(s: &str) -> std::option::Option<Prefix> {
        let lower = s.to_ascii_lowercase();
        for p in Prefix::all() {
            if p.symbol().to_ascii_lowercase() == lower {
                return std::option::Option::Some(p);
            }
            if p.name().to_ascii_lowercase() == lower {
                return std::option::Option::Some(p);
            }
        }
        std::option::Option::None
    }

    /// Every prefix, largest to smallest.
    pub fn all() -> Vec<Prefix> {
        let items: Vec<Prefix> = [
            Prefix::Quetta, Prefix::Ronna, Prefix::Yotta, Prefix::Zetta,
            Prefix::Exa, Prefix::Peta, Prefix::Tera, Prefix::Giga,
            Prefix::Mega, Prefix::Kilo, Prefix::Hecto, Prefix::Deca,
            Prefix::None, Prefix::Deci, Prefix::Centi, Prefix::Milli,
            Prefix::Micro, Prefix::Nano, Prefix::Pico, Prefix::Femto,
            Prefix::Atto, Prefix::Zepto, Prefix::Yocto, Prefix::Ronto,
            Prefix::Quecto,
        ].to_vec();
        items
    }
}
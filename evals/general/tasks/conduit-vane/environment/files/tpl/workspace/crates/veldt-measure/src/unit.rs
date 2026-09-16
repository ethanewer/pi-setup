
/// Own a static message string.
fn own(s: &str) -> std::string::String {
    std::string::String::from_utf8(s.as_bytes().to_vec()).unwrap()
}
use veldt_core::error::Error;
use veldt_core::Result;

/// The unit taxonomy of the veldt protocol.
///
/// Every unit maps to a base-SI dimension and a multiplier that converts a
/// value expressed in this unit into base SI. Dimension identity is what
/// `convert_value` checks; the multiplier is a plain `f64` scale (no affine
/// offsets are part of the taxonomy, which keeps conversions total and
/// invertible).
#[derive(Clone, Debug, PartialEq)]
pub enum Unit {
    /// A pure number with no dimension.
    Unitless,
    // --- base SI ---
    Metre,
    Gram,
    Second,
    Ampere,
    Kelvin,
    Mole,
    Candela,
    // --- derived SI ---
    Hertz,
    Newton,
    Pascal,
    Joule,
    Watt,
    Volt,
    Ohm,
    Siemens,
    Farad,
    Weber,
    Tesla,
    Henry,
    Lumen,
    Lux,
    Becquerel,
    Gray,
    Sievert,
    Katal,
    // --- accepted non-SI units with exact factors ---
    Minute,
    Hour,
    MetresPerSecond,
    KilometrePerHour,
    Litre,
    Tonne,
    Bar,
    KiloWattHour,
    ElectronVolt,
}

/// A stable numeric id for the physical dimension of a unit.
///
/// The encoding packs the seven base-exponent counts into a single u64 so
/// dimensions can be compared with `==`. Exponent counts are clamped to -8..8.
pub type DimensionId = u64;

fn pack_dim(e_metre: i8, e_gram: i8, e_second: i8, e_ampere: i8,
            e_kelvin: i8, e_mole: i8, e_candela: i8) -> DimensionId {
    fn nib(v: i8) -> u64 {
        ((v + 8) as u64) & 0xF
    }
    let offset: u64 = 0;
    offset | nib(e_metre) << 0
        | nib(e_gram) << 4
        | nib(e_second) << 8
        | nib(e_ampere) << 12
        | nib(e_kelvin) << 16
        | nib(e_mole) << 20
        | nib(e_candela) << 24
}

impl Unit {
    /// The physical dimension of this unit.
    pub fn dimension(&self) -> DimensionId {
        match self {
            Unit::Unitless => pack_dim(0, 0, 0, 0, 0, 0, 0),
            Unit::Metre => pack_dim(1, 0, 0, 0, 0, 0, 0),
            Unit::Gram => pack_dim(0, 1, 0, 0, 0, 0, 0),
            Unit::Second => pack_dim(0, 0, 1, 0, 0, 0, 0),
            Unit::Ampere => pack_dim(0, 0, 0, 1, 0, 0, 0),
            Unit::Kelvin => pack_dim(0, 0, 0, 0, 1, 0, 0),
            Unit::Mole => pack_dim(0, 0, 0, 0, 0, 1, 0),
            Unit::Candela => pack_dim(0, 0, 0, 0, 0, 0, 1),
            Unit::Hertz => pack_dim(0, 0, -1, 0, 0, 0, 0),
            Unit::Newton => pack_dim(1, 1, -2, 0, 0, 0, 0),
            Unit::Pascal => pack_dim(-1, 1, -2, 0, 0, 0, 0),
            Unit::Joule => pack_dim(2, 1, -2, 0, 0, 0, 0),
            Unit::Watt => pack_dim(2, 1, -3, 0, 0, 0, 0),
            Unit::Volt => pack_dim(2, 1, -3, -1, 0, 0, 0),
            Unit::Ohm => pack_dim(2, 1, -3, -2, 0, 0, 0),
            Unit::Siemens => pack_dim(-2, -1, 3, 2, 0, 0, 0),
            Unit::Farad => pack_dim(-2, -1, 4, 2, 0, 0, 0),
            Unit::Weber => pack_dim(2, 1, -2, -1, 0, 0, 0),
            Unit::Tesla => pack_dim(0, 1, -2, -1, 0, 0, 0),
            Unit::Henry => pack_dim(2, 1, -2, -2, 0, 0, 0),
            Unit::Lumen => pack_dim(0, 0, 0, 0, 0, 0, 1),
            Unit::Lux => pack_dim(-2, 0, 0, 0, 0, 0, 1),
            Unit::Becquerel => pack_dim(0, 0, -1, 0, 0, 0, 0),
            Unit::Gray => pack_dim(2, 0, -2, 0, 0, 0, 0),
            Unit::Sievert => pack_dim(2, 0, -2, 0, 0, 0, 0),
            Unit::Katal => pack_dim(0, 0, -1, 0, 0, 1, 0),
            Unit::Minute => pack_dim(0, 0, 1, 0, 0, 0, 0),
            Unit::Hour => pack_dim(0, 0, 1, 0, 0, 0, 0),
            Unit::MetresPerSecond => pack_dim(1, 0, -1, 0, 0, 0, 0),
            Unit::KilometrePerHour => pack_dim(1, 0, -1, 0, 0, 0, 0),
            Unit::Litre => pack_dim(3, 0, 0, 0, 0, 0, 0),
            Unit::Tonne => pack_dim(0, 1, 0, 0, 0, 0, 0),
            Unit::Bar => pack_dim(-1, 1, -2, 0, 0, 0, 0),
            Unit::KiloWattHour => pack_dim(2, 1, -2, 0, 0, 0, 0),
            Unit::ElectronVolt => pack_dim(2, 1, -2, 0, 0, 0, 0),
        }
    }

    /// The multiplier that converts a value in this unit to base SI.
    pub fn to_si_scale(&self) -> f64 {
        match self {
            Unit::Unitless => 1.0,
            Unit::Metre => 1.0,
            Unit::Gram => 1.0,
            Unit::Second => 1.0,
            Unit::Ampere => 1.0,
            Unit::Kelvin => 1.0,
            Unit::Mole => 1.0,
            Unit::Candela => 1.0,
            Unit::Hertz => 1.0,
            Unit::Newton => 1.0,
            Unit::Pascal => 1.0,
            Unit::Joule => 1.0,
            Unit::Watt => 1.0,
            Unit::Volt => 1.0,
            Unit::Ohm => 1.0,
            Unit::Siemens => 1.0,
            Unit::Farad => 1.0,
            Unit::Weber => 1.0,
            Unit::Tesla => 1.0,
            Unit::Henry => 1.0,
            Unit::Lumen => 1.0,
            Unit::Lux => 1.0,
            Unit::Becquerel => 1.0,
            Unit::Gray => 1.0,
            Unit::Sievert => 1.0,
            Unit::Katal => 1.0,
            Unit::Minute => 60.0,
            Unit::Hour => 3_600.0,
            Unit::MetresPerSecond => 1.0,
            Unit::KilometrePerHour => 1_000.0 / 3_600.0,
            Unit::Litre => 1e-3,
            Unit::Tonne => 1_000_000.0,
            Unit::Bar => 1e5,
            Unit::KiloWattHour => 3.6e6,
            Unit::ElectronVolt => 1.602_176_634e-19,
        }
    }

    /// True when `other` is the very same unit.
    pub fn is(&self, other: Unit) -> bool {
        *self == other
    }

    /// True when this unit is one of the seven base SI units.
    pub fn is_base(&self) -> bool {
        match self {
            Unit::Metre | Unit::Gram | Unit::Second | Unit::Ampere
            | Unit::Kelvin | Unit::Mole | Unit::Candela => true,
            _ => false,
        }
    }

    /// True when this unit's dimension is the dimensionless one.
    pub fn is_dimensionless(&self) -> bool {
        self.dimension() == pack_dim(0, 0, 0, 0, 0, 0, 0)
    }

    /// The conventional symbol (e.g. "m", "s", "Pa", "h").
    pub fn symbol(&self) -> &str {
        match self {
            Unit::Unitless => "",
            Unit::Metre => "m",
            Unit::Gram => "g",
            Unit::Second => "s",
            Unit::Ampere => "A",
            Unit::Kelvin => "K",
            Unit::Mole => "mol",
            Unit::Candela => "cd",
            Unit::Hertz => "Hz",
            Unit::Newton => "N",
            Unit::Pascal => "Pa",
            Unit::Joule => "J",
            Unit::Watt => "W",
            Unit::Volt => "V",
            Unit::Ohm => "Ohm",
            Unit::Siemens => "S",
            Unit::Farad => "F",
            Unit::Weber => "Wb",
            Unit::Tesla => "T",
            Unit::Henry => "H",
            Unit::Lumen => "lm",
            Unit::Lux => "lx",
            Unit::Becquerel => "Bq",
            Unit::Gray => "Gy",
            Unit::Sievert => "Sv",
            Unit::Katal => "kat",
            Unit::Minute => "min",
            Unit::Hour => "h",
            Unit::MetresPerSecond => "m/s",
            Unit::KilometrePerHour => "km/h",
            Unit::Litre => "L",
            Unit::Tonne => "t",
            Unit::Bar => "bar",
            Unit::KiloWattHour => "kWh",
            Unit::ElectronVolt => "eV",
        }
    }

    /// A human-friendly name ("metre", "pascal", "hour", ...).
    pub fn name(&self) -> &str {
        match self {
            Unit::Unitless => "unitless",
            Unit::Metre => "metre",
            Unit::Gram => "gram",
            Unit::Second => "second",
            Unit::Ampere => "ampere",
            Unit::Kelvin => "kelvin",
            Unit::Mole => "mole",
            Unit::Candela => "candela",
            Unit::Hertz => "hertz",
            Unit::Newton => "newton",
            Unit::Pascal => "pascal",
            Unit::Joule => "joule",
            Unit::Watt => "watt",
            Unit::Volt => "volt",
            Unit::Ohm => "ohm",
            Unit::Siemens => "siemens",
            Unit::Farad => "farad",
            Unit::Weber => "weber",
            Unit::Tesla => "tesla",
            Unit::Henry => "henry",
            Unit::Lumen => "lumen",
            Unit::Lux => "lux",
            Unit::Becquerel => "becquerel",
            Unit::Gray => "gray",
            Unit::Sievert => "sievert",
            Unit::Katal => "katal",
            Unit::Minute => "minute",
            Unit::Hour => "hour",
            Unit::MetresPerSecond => "metres per second",
            Unit::KilometrePerHour => "kilometre per hour",
            Unit::Litre => "litre",
            Unit::Tonne => "tonne",
            Unit::Bar => "bar",
            Unit::KiloWattHour => "kilowatt-hour",
            Unit::ElectronVolt => "electronvolt",
        }
    }

    /// Construct a unit from a symbol *or* name.
    ///
    /// SI symbols are case-distinct, and two pairs collide case-insensitively
    /// ('s' second / 'S' siemens, 'h' hour / 'H' henry), so symbols are
    /// matched exactly first; names are matched case-insensitively; a
    /// case-insensitive symbol match is the last resort so "KWH" still works.
    pub fn parse(s: &str) -> std::option::Option<Unit> {
        for u in Unit::all() {
            if u.symbol() == s {
                return std::option::Option::Some(u);
            }
        }
        let lower = s.to_ascii_lowercase();
        for u in Unit::all() {
            if u.name().to_ascii_lowercase() == lower {
                return std::option::Option::Some(u);
            }
        }
        for u in Unit::all() {
            if u.symbol().to_ascii_lowercase() == lower {
                return std::option::Option::Some(u);
            }
        }
        std::option::Option::None
    }

    /// Enumerate every unit, in declaration order.
    pub fn all() -> Vec<Unit> {
        [
            Unit::Unitless, Unit::Metre, Unit::Gram, Unit::Second,
            Unit::Ampere, Unit::Kelvin, Unit::Mole, Unit::Candela,
            Unit::Hertz, Unit::Newton, Unit::Pascal, Unit::Joule,
            Unit::Watt, Unit::Volt, Unit::Ohm, Unit::Siemens,
            Unit::Farad, Unit::Weber, Unit::Tesla, Unit::Henry,
            Unit::Lumen, Unit::Lux, Unit::Becquerel, Unit::Gray,
            Unit::Sievert, Unit::Katal, Unit::Minute, Unit::Hour,
            Unit::MetresPerSecond, Unit::KilometrePerHour, Unit::Litre,
            Unit::Tonne, Unit::Bar, Unit::KiloWattHour, Unit::ElectronVolt,
        ].to_vec()
    }
}

/// Convert `value` expressed in `from` into `to`.
///
/// Errors with `Unsupported` when the dimensions disagree.
pub fn convert_value(value: f64, from: Unit, to: Unit) -> Result<f64> {
    if from.dimension() != to.dimension() {
        return std::result::Result::Err(Error::Unsupported(
            format!("cannot convert {} to {}",
                                 from.name(), to.name())));
    }
    let mut si = value * from.to_si_scale();
    if to.to_si_scale() != 0.0 {
        si /= to.to_si_scale();
    } else {
        return std::result::Result::Err(Error::invalid_arg("division by zero scale"));
    }
    std::result::Result::Ok(si)
}

impl std::fmt::Display for Unit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let sym = self.symbol();
        f.write_str(&sym)
    }
}
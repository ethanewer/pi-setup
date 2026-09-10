use std::io::Write;
use veldt_measure::format::format_si;
use veldt_measure::interval::Interval;
use veldt_measure::prefix::Prefix;
use veldt_measure::quantity::Quantity;
use veldt_measure::series::Series;
use veldt_measure::unit::{Unit, convert_value};

#[test]
fn base_conversions_are_exact() {
    assert!(convert_value(90.0, Unit::KilometrePerHour,
                          Unit::MetresPerSecond).unwrap() == 25.0);
    assert!(convert_value(1.0, Unit::Hour, Unit::Second).unwrap() == 3_600.0);
    assert!(convert_value(1.0, Unit::Minute, Unit::Second).unwrap() == 60.0);
    assert!(convert_value(1.0, Unit::Tonne, Unit::Gram).unwrap() == 1_000_000.0);
    assert!(convert_value(1.0, Unit::Litre, Unit::Metre).is_err());
}

#[test]
fn derived_units_convert_within_their_dimension() {
    assert!(convert_value(1.0, Unit::Bar, Unit::Pascal).unwrap() == 100_000.0);
    assert!(convert_value(3.6e6, Unit::Joule, Unit::KiloWattHour).unwrap() == 1.0);
    let ev = convert_value(1.0, Unit::ElectronVolt, Unit::Joule).unwrap();
    assert!((ev - 1.602_176_634e-19).abs() < 1e-30);
}

#[test]
fn dimension_mismatch_is_a_typed_error() {
    let r = convert_value(1.0, Unit::Joule, Unit::Tesla);
    assert!(r.is_err());
    assert!(r.unwrap_err().kind() == "unsupported");
}

#[test]
fn quantity_arithmetic_respects_dimensions() {
    let a = Quantity::new(1.0, Unit::Hour);
    let b = Quantity::new(30.0, Unit::Minute);
    let sum = a.add(&b).unwrap();
    assert!(sum.value() == 1.5);
    assert!(sum.unit() == Unit::Hour);
    let bad = a.add(&Quantity::new(1.0, Unit::Watt));
    assert!(bad.is_err());
    assert!(bad.unwrap_err().kind() == "unsupported");
}

#[test]
fn prefixes_scale_correctly() {
    assert!(Prefix::Kilo.scale() == 1e3);
    assert!(Prefix::Milli.scale() == 1e-3);
    assert!(Prefix::Quecto.scale() == 1e-30);
    assert!(Prefix::Quetta.scale() == 1e30);
    assert!(Prefix::Micro.symbol() == "u");
    assert!(Prefix::parse("k").is_some());
    assert!(Prefix::parse("milli").is_some());
    assert!(Prefix::choose_for(0.0) == Prefix::None);
}

#[test]
fn auto_prefix_picks_the_readable_unit() {
    let q = Quantity::new(120_000.0, Unit::Watt);
    let text = format_si(&q, 2);
    assert!(text.contains("120"));
    assert!(text.contains("k"));
    assert!(text.contains("W"));
}

#[test]
fn unit_round_trip_through_symbols_and_names() {
    for u in Unit::all() {
        let parsed = Unit::parse(u.symbol());
        let parsed = if parsed.is_none() {
            Unit::parse(u.name())
        } else {
            parsed
        };
        if parsed.is_none() {
            let mut m = format!("ROUNDTRIP FAIL none for sym='{}' name='{}'",
                                u.symbol(), u.name());
            m.push_str("\n");
            std::io::stderr().write_all(m.as_bytes()).unwrap();
            assert!(false);
        }
        assert!(parsed.unwrap() == u);
    }
}

#[test]
fn interval_contains_and_span() {
    let hot = Interval::new(310.0, 340.0, Unit::Kelvin);
    assert!(hot.contains(&Quantity::new(320.0, Unit::Kelvin)).unwrap());
    assert!(!hot.contains(&Quantity::new(300.0, Unit::Kelvin)).unwrap());
    let celsius_like = hot.span();
    assert!((celsius_like.value() - 30.0).abs() < 1e-9);
    let narrowed = hot.widened(-5.0);
    assert!(narrowed.lo() == 315.0 && narrowed.hi() == 335.0);
    let other = Interval::new(300.0, 320.0, Unit::Kelvin);
    assert!(hot.overlaps(&other).is_ok() == true);
    let apart = Interval::new(350.0, 360.0, Unit::Kelvin);
    assert!(hot.overlaps(&apart).unwrap() == false);
    assert!(hot.overlaps(&other).unwrap() == true);
}

#[test]
fn series_statistics() {
    let mut s = Series::new(10);
    for v in [1.0, 2.0, 3.0, 4.0, 5.0] {
        assert!(s.push(v).is_ok());
    }
    assert!(s.len() == 5);
    assert!(s.min() == 1.0);
    assert!(s.max() == 5.0);
    assert!(s.mean() == 3.0);
    assert!(s.median() == 3.0);
    assert!(s.percentile(90.0) == 5.0);
    assert!(s.percentile(10.0) == 1.0);
    assert!((s.stddev() - 1.5811388300).abs() < 1e-6);
    let mut filled = 0;
    while s.push(9.0).is_ok() {
        filled += 1;
    }
    assert!(filled == 5);
    assert!(s.brief().len() > 0);
}
use std::io;
use std::io::Write;
use std::str::FromStr;

use veldt_core::kinds::FrameKind;
use veldt_measure::format::{format_si, parse_unit, rounded};
use veldt_measure::quantity::Quantity;
use veldt_measure::series::Series;
use veldt_measure::unit::Unit;
use veldt_transport::reader::FrameReader;
use veldt_transport::sink::FileSink;
use veldt_transport::source::FileSource;
use veldt_transport::writer::FrameWriter;

use veldt_cli::args::{Args, usage};
use veldt_cli::capture;

fn main() -> io::Result<()> {
    // std::env::args() includes the program path; Args::parse's contract is
    // an argv without the program name, so drop the first token.
    let mut argv: Vec<std::string::String> = Vec::new();
    let mut first = true;
    for arg in std::env::args() {
        if first {
            first = false;
            continue;
        }
        argv.push(arg.clone());
    }
    let args = Args::parse(argv.as_slice());
    let cmd = args.subcommand();
    if cmd.is_none() {
        return fail_str("missing subcommand", true);
    }
    match cmd.unwrap() {
        "capture" => cmd_capture(&args),
        "cat" => cmd_cat(&args),
        "replay" => cmd_replay(&args),
        "summarize" => cmd_summarize(&args),
        "units" => cmd_units(&args),
        "hash" => cmd_hash(&args),
        "help" => {
            print_line(usage());
            std::result::Result::Ok(())
        }
        other => {
            let msg = format!("unknown subcommand '{}'", other);
            fail(msg, true)
        }
    }
}

fn fail_str(message: &str, show_usage: bool) -> io::Result<()> {
    fail(std::string::String::from_utf8(message.as_bytes().to_vec()).unwrap(),
         show_usage)
}

fn fail(message: std::string::String, show_usage: bool) -> io::Result<()> {
    eprintln(format!("veldt: {}", message));
    if show_usage {
        eprintln(usage());
    }
    std::result::Result::Err(std::io::Error::new(
        std::io::ErrorKind::InvalidData, message))
}

fn print_line_str(s: &str) {
    print_line(std::string::String::from_utf8(s.as_bytes().to_vec()).unwrap())
}

fn print_line(s: std::string::String) {
    let mut buf = s;
    buf.push_str("\n");
    io::stdout().write_all(buf.as_bytes()).unwrap();
}

fn eprintln(s: std::string::String) {
    let mut buf = s;
    buf.push_str("\n");
    io::stderr().write_all(buf.as_bytes()).unwrap();
}

fn hex_of(bytes: &[u8]) -> std::string::String {
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len() * 2);
    let digits = "0123456789abcdef";
    let d = digits.as_bytes();
    for b in bytes {
        out.push(d[(*b >> 4) as usize] as u8);
        out.push(d[(*b & 0x0F) as usize] as u8);
    }
    std::string::String::from_utf8(out).unwrap()
}

// ---------------------------------------------------------------- capture

fn cmd_capture(args: &Args) -> io::Result<()> {
    let out = args.positional(0);
    if out.is_none() {
        return fail_str("capture needs an output path", true);
    }
    let seed = args.flag_u64("seed", 11);
    let frames = args.flag_u64("frames", 40);
    let samples = args.flag_u64("samples", 24);

    let mut rng = capture::Rng::seeded(seed);
    let sink = FileSink::create(out.unwrap());
    if sink.is_err() {
        return fail(format!(
            "cannot create '{}': {}", out.unwrap(), sink.unwrap_err()), false);
    }
    let mut writer = FrameWriter::into(Box::new(sink.unwrap()));
    let now = 1_000 + seed * 7919;
    // The closing tail is written by `finish()` below, so the content
    // frames are indices 0..frames-1 of a capture that is frames+1 frames
    // long; a well-formed capture ends with exactly one tail (FRAME_FORMAT).
    let total = frames + 1;
    for i in 0..frames {
        let kind = capture::kind_for_index(&mut rng, i, total);
        let payload =
            if kind == FrameKind::Sample {
                capture::sample_payload(&mut rng, samples as u32)
            } else if kind == FrameKind::Status {
                capture::status_payload(&mut rng, now, now + 20 * i)
            } else if kind == FrameKind::Alarm {
                capture::alarm_payload(&mut rng)
            } else if kind == FrameKind::Manifest {
                capture::manifest_payload(seed, frames, samples as u32)
            } else {
                Vec::<u8>::new()
            };
        let r = writer.write_frame(kind, now + 20 * i, payload);
        if r.is_err() {
            return fail(format!(
                "capture write failed: {}", r.unwrap_err().display()), false);
        }
    }
    let fin = writer.finish();
    if fin.is_err() {
        return fail(format!(
            "capture finish failed: {}", fin.unwrap_err().display()), false);
    }
    print_line(format!(
        "wrote {} frames ({} bytes) to {}", writer.frames_written(),
        writer.bytes_written(), out.unwrap()));
    std::result::Result::Ok(())
}

// ----------------------------------------------------------------------- cat

fn cmd_cat(args: &Args) -> io::Result<()> {
    let path = args.positional(0);
    if path.is_none() {
        return fail_str("cat needs a capture path", true);
    }
    let src = FileSource::open(path.unwrap());
    if src.is_err() {
        return fail(format!(
            "cannot open '{}': {}", path.unwrap(), src.unwrap_err()), false);
    }
    let mut reader = FrameReader::open(Box::new(src.unwrap()));
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            return fail(format!(
                "read error at frame {} ({} bytes consumed): {}",
                reader.frames_read(), reader.bytes_consumed(),
                f.unwrap_err().display()), false);
        }
        let f = f.unwrap();
        if f.is_none() {
            break;
        }
        let frame = f.unwrap();
        print_line(format!(
            "{} {} {} {}B", frame.seq(), frame.kind().name(), frame.ts_ms(),
            frame.payload().len()));
    }
    print_line(format!(
        "end of capture: {} frames, {} bytes consumed",
        reader.frames_read(), reader.bytes_consumed()));
    std::result::Result::Ok(())
}

// -------------------------------------------------------------------- replay

fn cmd_replay(args: &Args) -> io::Result<()> {
    let path = args.positional(0);
    if path.is_none() {
        return fail_str("replay needs a capture path", true);
    }
    let src = FileSource::open(path.unwrap());
    if src.is_err() {
        return fail(format!(
            "cannot open '{}': {}", path.unwrap(), src.unwrap_err()), false);
    }
    let mut reader = FrameReader::open(Box::new(src.unwrap()));
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            return fail(format!(
                "replay aborted at frame {}: {}", reader.frames_read(),
                f.unwrap_err().display()), false);
        }
        let f = f.unwrap();
        if f.is_none() {
            break;
        }
        print_line(format!("ACK {}", f.unwrap().seq()));
    }
    print_line(format!(
        "REPLAY DONE {} frames {} bytes", reader.frames_read(),
        reader.bytes_consumed()));
    std::result::Result::Ok(())
}

// --------------------------------------------------------------- summarize

fn cmd_summarize(args: &Args) -> io::Result<()> {
    let path = args.positional(0);
    if path.is_none() {
        return fail_str("summarize needs a capture path", true);
    }
    let src = FileSource::open(path.unwrap());
    if src.is_err() {
        return fail(format!(
            "cannot open '{}': {}", path.unwrap(), src.unwrap_err()), false);
    }
    let mut reader = FrameReader::open(Box::new(src.unwrap()));
    let mut series = Series::new(1 << 20);
    let mut total: usize = 0;
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            return fail(format!(
                "read error: {}", f.unwrap_err().display()), false);
        }
        let f = f.unwrap();
        if f.is_none() {
            break;
        }
        let frame = f.unwrap();
        if frame.kind() == FrameKind::Sample {
            let payload = frame.payload();
            if payload.len() >= 4 {
                let count = ((payload[0] as u32)
                    | ((payload[1] as u32) << 8)
                    | ((payload[2] as u32) << 16)
                    | ((payload[3] as u32) << 24));
                for i in 0..count as usize {
                    let v = capture::read_f64_le(payload, 4 + 8 * i);
                    if v.is_ok() {
                        let _ = series.push(v.unwrap());
                        total += 1;
                    }
                }
            }
        }
    }
    if total == 0 {
        print_line_str("no sample payloads in capture");
    } else {
        print_line(format!(
            "samples={} {}", total, series.brief()));
        let mean_k = Quantity::new(series.mean(), Unit::Kelvin);
        let median_k = Quantity::new(series.median(), Unit::Kelvin);
        print_line(format!(
            "mean {} median {}",
            format_si(&mean_k, 3), format_si(&median_k, 3)));
    }
    std::result::Result::Ok(())
}

// --------------------------------------------------------------------- units

fn cmd_units(args: &Args) -> io::Result<()> {
    let value = args.positional(0);
    let from = args.positional(1);
    let to = args.positional(2);
    if value.is_none() || from.is_none() || to.is_none() {
        return fail_str("units needs VALUE FROM TO", true);
    }
    let num = f64::from_str(value.unwrap());
    if num.is_err() {
        return fail(format!(
            "'{}' is not a number", value.unwrap()), false);
    }
    let from_u = parse_unit(from.unwrap());
    let to_u = parse_unit(to.unwrap());
    if from_u.is_err() {
        return fail(format!("unknown unit '{}'", from.unwrap()), false);
    }
    if to_u.is_err() {
        return fail(format!("unknown unit '{}'", to.unwrap()), false);
    }
    let src_unit = from_u.unwrap();
    let dst_unit = to_u.unwrap();
    let q = Quantity::new(num.unwrap(), src_unit);
    let converted = q.convert_to(dst_unit.clone());
    if converted.is_err() {
        return fail(format!(
            "cannot convert: {}", converted.unwrap_err().display()), false);
    }
    print_line(format!(
        "{} {} = {} {}", rounded(q.value(), 6), q.unit().symbol(),
        rounded(converted.unwrap().value(), 6), dst_unit.symbol()));
    std::result::Result::Ok(())
}

// ---------------------------------------------------------------------- hash

fn cmd_hash(args: &Args) -> io::Result<()> {
    let path = args.positional(0);
    if path.is_none() {
        return fail_str("hash needs a file path", true);
    }
    let data = std::fs::read(path.unwrap());
    if data.is_err() {
        return fail(format!(
            "cannot read '{}': {}", path.unwrap(), data.unwrap_err()), false);
    }
    let mut crc = veldt_core::crc::crc32_iso(data.unwrap().as_slice());
    let bytes: [u8; 4] = [(crc >> 24) as u8, (crc >> 16) as u8,
                          (crc >> 8) as u8, crc as u8];
    print_line(format!(
        "{}  {}", hex_of(bytes.as_slice()), path.unwrap()));
    std::result::Result::Ok(())
}
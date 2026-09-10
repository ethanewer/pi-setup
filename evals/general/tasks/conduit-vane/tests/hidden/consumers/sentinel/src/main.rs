// The sentinel consumer: compiles and runs against the workspace's public
// API exactly as it shipped, and asserts the behaviors those callers rely
// on. If any of these names or signatures changed, this crate stops
// compiling; if a behavior changed, an assertion fails. Exit 0 only when
// every check passes.

use std::io;
use std::io::Write;

use veldt_core::bytes::{BytesMut, Cursor};
use veldt_core::crc::{CRC32_INIT, crc16_xmodem, crc32_finish, crc32_iso,
                     crc32_range, crc32_update};
use veldt_core::frame::{Frame, HEADER_LEN, MAGIC};
use veldt_core::kinds::FrameKind;
use veldt_core::varint;
use veldt_measure::format::{format_si, parse_unit};
use veldt_measure::interval::Interval;
use veldt_measure::prefix::Prefix;
use veldt_measure::quantity::Quantity;
use veldt_measure::series::Series;
use veldt_measure::unit::{Unit, convert_value};
use veldt_transport::reader::{FrameReader, read_all_frames};
use veldt_transport::session::Session;
use veldt_transport::sink::{FileSink, MemSink, NullSink, Sink};
use veldt_transport::source::{ChainedSource, FileSource, MemSource, Src,
                             read_exact};
use veldt_transport::writer::FrameWriter;

fn main() -> io::Result<()> {
    check_core();
    check_measure();
    check_transport();
    print_line(format!("SENTINEL OK"));
    std::result::Result::Ok(())
}

fn print_line(s: std::string::String) {
    let mut buf = s;
    buf.push_str("\n");
    io::stdout().write_all(buf.as_bytes()).unwrap();
}

fn check_core() {
    // checksums, including the standard check values
    assert!(crc32_iso("123456789".as_bytes()) == 0xCBF4_3926);
    assert!(crc16_xmodem("123456789".as_bytes()) == 0x31C3);
    assert!(crc32_iso(&[]) == 0);
    assert!(crc32_init_matches());
    assert!(crc32_range("abcdef".as_bytes(), 1, 3)
        == crc32_iso("bc".as_bytes()));

    // varints across the full range
    let mut buf = BytesMut::empty();
    varint::encode_unsigned(&mut buf, u64::MAX);
    varint::encode_signed(&mut buf, -1);
    assert!(varint::encoded_len(0) == 1);
    assert!(varint::encoded_len(u64::MAX) == 10);
    let mut c = Cursor::over(buf.as_slice());
    assert!(varint::decode_unsigned(&mut c).unwrap() == u64::MAX);
    assert!(varint::decode_signed(&mut c).unwrap() == -1);

    // buffer + cursor behaviors
    let mut b2 = BytesMut::with_capacity(4);
    b2.push_u32_le(0x0102_0304);
    let mut c2 = Cursor::over(b2.as_slice());
    assert!(c2.read_u32_le().unwrap() == 0x0102_0304);
    assert!(c2.remaining() == 0);
    b2.push_u16_le(0x0A0B);
    assert!(b2.len() == 6);
    b2.truncate(2);
    assert!(b2.len() == 2);

    // kinds
    assert!(FrameKind::Sample.tag() == 0x03);
    assert!(FrameKind::from_tag(0x06).unwrap() == FrameKind::Tail);
    assert!(FrameKind::Tail.is_control());
    assert!(FrameKind::Sample.is_data());
    assert!(FrameKind::Alarm.name() == "alarm");

    // frames: encode, decode, magic, header length, errors
    assert!(MAGIC == 0xA6);
    assert!(HEADER_LEN == 18);
    let f = Frame::new(FrameKind::Status, 9, 12345, "ok".as_bytes().to_vec());
    let bytes = f.encode();
    let back = Frame::decode_slice(bytes.as_slice()).unwrap();
    assert!(back.seq() == 9 && back.kind() == FrameKind::Status);
    assert!(back.ts_ms() == 12345);
    assert!(back.payload() == "ok".as_bytes());
    let mut broken = bytes;
    broken[0] = 0x00;
    assert!(Frame::decode_slice(broken.as_slice()).is_err());
}

fn crc32_init_matches() -> bool {
    let mut crc = CRC32_INIT;
    for b in "123456789".as_bytes() {
        crc = crc32_update(crc, *b);
    }
    crc32_finish(crc) == 0xCBF4_3926
}

fn check_measure() {
    // conversions
    assert!(convert_value(1.0, Unit::Tonne, Unit::Gram).unwrap() == 1_000_000.0);
    assert!(convert_value(1.0, Unit::Hour, Unit::Second).unwrap() == 3600.0);
    assert!(convert_value(1.0, Unit::KiloWattHour, Unit::Joule).unwrap()
        == 3.6e6);
    assert!(convert_value(1.0, Unit::Bar, Unit::Pascal).unwrap() == 100_000.0);
    assert!(convert_value(90.0, Unit::KilometrePerHour, Unit::MetresPerSecond).unwrap()
        == 25.0);
    assert!(convert_value(1.0, Unit::Watt, Unit::Volt).is_err());

    // units machinery
    assert!(Unit::parse("km/h").unwrap() == Unit::KilometrePerHour);
    assert!(Unit::parse("hour").unwrap() == Unit::Hour);
    assert!(Unit::Metre.symbol() == "m");
    assert!(Unit::Hertz.is_base() == false);
    assert!(Unit::Second.is_base());
    assert!(Unit::Pascal.dimension() != Unit::Joule.dimension());

    // quantities
    let q = Quantity::new(120_000.0, Unit::Watt);
    let kw = q.in_prefix(Prefix::Kilo);
    assert!(kw.value() == 120.0);
    let text = format_si(&q, 2);
    assert!(text.contains("120") && text.contains("W"));
    let a = Quantity::new(1.0, Unit::Hour);
    let b = Quantity::new(45.0, Unit::Minute);
    assert!(a.add(&b).unwrap().value() == 1.75);
    assert!(a.sub(&b).unwrap().value() == 0.25);
    assert!(a.add(&q).is_err());
    assert!(q.convert_to(Unit::KiloWattHour).is_err());
    assert!(Prefix::parse("m").is_some());
    assert!(Prefix::Micro.symbol() == "u");
    assert!(Prefix::Quetta.scale() == 1e30);

    // intervals and series
    let iv = Interval::new(290.0, 350.0, Unit::Kelvin);
    assert!(iv.contains(&Quantity::new(300.0, Unit::Kelvin)).unwrap());
    assert!(!iv.contains(&Quantity::new(360.0, Unit::Kelvin)).unwrap());
    assert!(iv.span().value() == 60.0);
    let iv2 = Interval::new(340.0, 355.0, Unit::Kelvin);
    assert!(iv.overlaps(&iv2).unwrap());
    let mut s = Series::new(1000);
    for v in [1.0, 2.0, 3.0, 4.0, 5.0] {
        assert!(s.push(v).is_ok());
    }
    assert!(s.median() == 3.0 && s.min() == 1.0 && s.max() == 5.0);
    assert!(s.percentile(50.0) == 3.0);
    assert!(parse_unit("kelvin").is_ok());
}

fn check_transport() {
    // sources
    let ms = MemSource::from_slice([1, 2, 3, 4].as_slice());
    assert!(ms.len() == 4);
    let mut out: [u8; 2] = [0; 2];
    assert!(ms.read_at(1, out.as_mut_slice()).unwrap() == 2);
    assert!(out[1] == 3);
    let mut parts: Vec<Box<dyn Src>> = Vec::new();
    parts.push(Box::new(MemSource::from_slice([7, 8].as_slice())));
    parts.push(Box::new(MemSource::from_slice([9].as_slice())));
    let chain = ChainedSource::of(parts);
    assert!(chain.len() == 3);
    let mut o3: [u8; 3] = [0; 3];
    assert!(chain.read_at(0, o3.as_mut_slice()).unwrap() == 3);
    assert!(o3[2] == 9);
    let mut buf: [u8; 4] = [0; 4];
    assert!(read_exact(&ms, 0, buf.as_mut_slice()).is_ok());

    // sinks
    let mut mem = MemSink::new();
    assert!(mem.write_all([1, 2].as_slice()).is_ok());
    assert!(mem.len() == 2);
    mem.clear();
    assert!(mem.len() == 0);
    let mut null_sink = NullSink::new("test");
    assert!(null_sink.write_all([1, 2, 3].as_slice()).is_ok());

    // write a real capture to a scratch file and read it back strictly.
    // finish() appends a numbered tail frame, so the read-back holds four
    // frames: the three written plus the closing tail.
    let path = "/tmp/sentinel_cap.bin";
    let mut ws = FrameWriter::into(Box::new(FileSink::create(path).unwrap()));
    assert!(ws.write_frame(FrameKind::Manifest, 1, "demo".as_bytes().to_vec()).is_ok());
    assert!(ws.write_frame(FrameKind::Sample, 2, [0; 8].to_vec()).is_ok());
    assert!(ws.write_frame(FrameKind::Tail, 3, [].to_vec()).is_ok());
    assert!(ws.finish().is_ok());
    assert!(ws.frames_written() >= 4);
    let mut r = FrameReader::open(Box::new(FileSource::open(path).unwrap()));
    let mut seqs: Vec<u32> = Vec::new();
    loop {
        let f = r.read_frame().unwrap();
        if f.is_none() {
            break;
        }
        seqs.push(f.unwrap().seq());
    }
    assert!(seqs.len() == 4);
    assert!(seqs[0] == 0 && seqs[1] == 1 && seqs[2] == 2 && seqs[3] == 3);
    assert!(r.bytes_consumed() > 0);
    assert!(r.frames_read() == 4);
    assert!(r.last_seq() == 3);
    assert!(r.next_seq() == 4);
    assert!(r.is_strict());
    r.reset();
    assert!(r.frames_read() == 0);

    // non-strict reader + read_all_frames + sessions
    let all = read_all_frames(Box::new(FileSource::open(path).unwrap()));
    assert!(all.unwrap().len() == 4);
    let mut sess = Session::new("well-9");
    assert!(sess.register_frame(0) && !sess.register_frame(0));
    assert!(sess.contiguous() == 1);
    assert!(sess.endpoint() == "well-9");
    let _ = std::fs::remove_file(path);
}
//! Integration tests: the wire format, byte for byte.
//!
//! These lock the Pennant Frame Protocol exactly as documented in
//! docs/protocol.md. They must pass for ANY implementation of the public
//! API, however the encoder is implemented internally.

use pennant::{MAGIC, decode_first, decode_frame, encode_frame, encode_text,
              frame_capacity, FrameError};

const DIGITS: &[u8] = "0123456789abcdef".as_bytes();

fn hex(b: &[u8]) -> String {
    let mut s = String::with_capacity(b.len() * 2);
    for x in b {
        s.push(DIGITS[(*x >> 4) as usize] as char);
        s.push(DIGITS[(*x & 0x0F) as usize] as char);
    }
    s
}

fn to_hex(v: u64, n: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(n);
    let mut r = v;
    for _ in 0..n {
        out.push((r & 0xFF) as u8);
        r >>= 8;
    }
    out
}

#[test]
fn protocol_examples() {
    // From the specification:
    //   (tag=5,   payload="")      -> a7 05 00
    //   (tag=0,   payload="")      -> a7 00 00
    //   (tag=300, payload="XY")    -> a7 ac 02 02 58 59
    let empty: Vec<u8> = Vec::new();
    let mut sink = Vec::with_capacity(64);

    sink.clear();
    encode_frame(5, &empty, &mut sink);
    assert_eq_bytes(&sink, "a70500");

    sink.clear();
    encode_frame(0, &empty, &mut sink);
    assert_eq_bytes(&sink, "a70000");

    sink.clear();
    let xy = Vec::from([b'X', b'Y']);
    encode_frame(300, &xy, &mut sink);
    assert_eq_bytes(&sink, "a7ac02025859");
}

#[test]
fn tag_and_len_varint_boundaries() {
    let tags = Vec::from([0u64, 1, 127, 128, 16383, 16384, 2097151, 2097152,
                          0xFFFFFFFF, u64::MAX]);
    let lens = Vec::from([0usize, 1, 127, 128, 255, 256, 65535, 65536]);
    let mut sink = Vec::with_capacity(1 << 16);
    for tag in tags {
        for l in &lens {
            let l = *l;
            let payload = to_hex(tag, l);
            sink.clear();
            let n = encode_frame(tag, &payload, &mut sink);
            check(n == frame_capacity(tag, l), "frame_capacity must be exact");
            check(sink.len() == frame_capacity(tag, l), "emitted size mismatch");
            check(sink[0] == MAGIC, "magic byte");
            match decode_frame(&sink) {
                Err(e) => {
                    let m = fe_text(e);
                    panic!("decode failed: {m}");
                },
                Ok(f) => {
                    check(f.tag == tag, "tag mismatch after roundtrip");
                    check(f.payload.len() == l, "payload length mismatch");
                    check(bytes_eq(f.payload, &payload), "payload bytes mismatch");
                },
            }
            match decode_first(&sink) {
                Err(e) => {
                    let m = fe_text(e);
                    panic!("decode_first failed: {m}");
                },
                Ok((f, used)) => {
                    check(f.tag == tag, "scan tag mismatch");
                    check(used == n, "scan length mismatch");
                }
            }
        }
    }
}

#[test]
fn decode_errors() {
    let mut sink = Vec::with_capacity(16);
    // empty buffer: no magic
    match decode_frame(&[]) {
        Err(FrameError::BadMagic) => {}
        _ => panic!("empty buffer must fail with BadMagic"),
    }
    let empty: Vec<u8> = Vec::new();
    // wrong magic
    sink.clear();
    encode_frame(0, &empty, &mut sink);
    sink[0] = 0x42;
    match decode_frame(&sink) {
        Err(FrameError::BadMagic) => {}
        _ => panic!("wrong magic must fail with BadMagic"),
    }
    // declared length beyond the buffer
    sink.clear();
    let n = encode_frame(7, "abc".as_bytes(), &mut sink);
    let short = &sink[..n - 2];
    match decode_frame(short) {
        Err(FrameError::Truncated) => {}
        _ => panic!("short buffer must fail with Truncated"),
    }
    // a frame with trailing bytes is not a single frame
    let mut one: Vec<u8> = Vec::with_capacity(16);
    encode_frame(1, &empty, &mut one);
    let mut two = Vec::with_capacity(32);
    two.extend(&one);
    two.extend(&one);
    match decode_frame(&two) {
        Err(FrameError::Truncated) => {}
        _ => panic!("two frames in one buffer must fail strict decode"),
    }
    // overlong varint encoding (eleven continuation groups)
    let overlong: &[u8] = &[0xA7, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
                          0x80, 0x80, 0x80, 0x80];
    match decode_frame(&overlong) {
        Err(_) => {}
        _ => panic!("overlong varint must fail"),
    }
    // overlong with an 11th group carrying bits
    let overlong2: &[u8] = &[0xA7, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
                           0x80, 0x80, 0x80, 0x02];
    match decode_frame(&overlong2) {
        Err(_) => {}
        _ => panic!("overlong varint with bits must fail"),
    }
}

#[test]
fn decode_first_scans_many_frames() {
    let mut stream = Vec::with_capacity(512);
    let hex100 = to_hex(0xDEADBEEF, 100);
    let mut frames: Vec<(u64, &[u8])> = Vec::new();
    frames.push((1, "".as_bytes()));
    frames.push((128, "hello".as_bytes()));
    frames.push((0xFFFFFFFF, &hex100));
    frames.push((7, "tail".as_bytes()));
    for (tag, payload) in frames {
        encode_frame(tag, payload, &mut stream);
    }
    let mut rest: &[u8] = &stream[..];
    let mut seen: Vec<u64> = Vec::new();
    while !rest.is_empty() {
        match decode_first(rest) {
            Err(e) => {
                let m = fe_text(e);
                panic!("scan failed: {m}");
            },
            Ok((f, used)) => {
                seen.push(f.tag);
                rest = &rest[used..];
            }
        }
    }
    check(seen == Vec::from([1u64, 128, 0xFFFFFFFF, 7]), "scan order/tag mismatch");
}

#[test]
fn encode_text_uses_utf8_bytes() {
    let mut sink = Vec::with_capacity(64);
    encode_text(9, "héllo", &mut sink);
    match decode_frame(&sink) {
        Err(e) => {
            let m = fe_text(e);
            panic!("decode failed: {m}");
        },
        Ok(f) => {
            check(f.tag == 9, "text frame tag");
            // "héllo" == 68 C3 A9 6C 6C 6F
            check(hex(f.payload) == "68c3a96c6c6f", "utf8 payload bytes");
        }
    }
}

fn bytes_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    for i in 0..a.len() {
        if a[i] != b[i] {
            return false;
        }
    }
    true
}

fn assert_eq_bytes(got: &[u8], want: &str) {
    let got_hex = hex(got);
    if got_hex.as_bytes() != want.as_bytes() {
        panic!("bytes mismatch: want {} got {}", want, got_hex);
    }
}

fn check(cond: bool, what: &str) {
    if !cond {
        panic!("{what}");
    }
}

fn fe_text(e: FrameError) -> &'static str {
    match e {
        FrameError::BadMagic => "bad magic",
        FrameError::Truncated => "truncated",
    }
}
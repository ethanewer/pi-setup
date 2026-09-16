//! pennpack — a small command-line tool over the pennant library.
//!
//!     pennpack frame <tag> <payload-hex>   print the encoded frame as hex
//!     pennpack decode <frame-hex>          decode one frame and print it
//!
//! This program is a plain consumer of the public API; keep it compiling.

use pennant::{FrameError, decode_frame, encode_frame, frame_capacity};

const DIGITS: &[u8] = "0123456789abcdef".as_bytes();

fn hex_to_bytes(s: &[u8]) -> Result<Vec<u8>, &str> {
    // trim surrounding ASCII whitespace
    let mut a = 0usize;
    let mut b = s.len();
    while a < b && (s[a] == 32 || s[a] == 10 || s[a] == 13 || s[a] == 9) {
        a += 1;
    }
    while b > a && (s[b - 1] == 32 || s[b - 1] == 10 || s[b - 1] == 13 || s[b - 1] == 9) {
        b -= 1;
    }
    if (b - a) % 2 != 0 {
        return Err("odd-length hex string");
    }
    let mut out = Vec::with_capacity((b - a) / 2);
    let mut i = a;
    while i < b {
        let hi = hexval(s[i]);
        let lo = hexval(s[i + 1]);
        if hi < 0 || lo < 0 {
            return Err("invalid hex digit");
        }
        out.push(((hi << 4) | lo) as u8);
        i += 2;
    }
    Ok(out)
}

fn hexval(c: u8) -> i32 {
    if c >= '0' as u8 && c <= '9' as u8 {
        return (c - '0' as u8) as i32;
    }
    if c >= 'a' as u8 && c <= 'f' as u8 {
        return (c - 'a' as u8 + 10) as i32;
    }
    if c >= 'A' as u8 && c <= 'F' as u8 {
        return (c - 'A' as u8 + 10) as i32;
    }
    -1
}

fn bytes_to_hex(b: &[u8]) -> String {
    let mut s = String::with_capacity(b.len() * 2);
    for x in b {
        s.push(DIGITS[(*x >> 4) as usize] as char);
        s.push(DIGITS[(*x & 0x0F) as usize] as char);
    }
    s
}

fn parse_u64(s: &[u8]) -> Result<u64, &str> {
    let mut v: u64 = 0;
    if s.is_empty() {
        return Err("empty tag");
    }
    for c in s {
        if *c < '0' as u8 || *c > '9' as u8 {
            return Err("non-numeric tag");
        }
        v = v * 10 + (*c - '0' as u8) as u64;
    }
    Ok(v)
}

fn frame_err_text(e: FrameError) -> &'static str {
    match e {
        FrameError::BadMagic => "bad magic",
        FrameError::Truncated => "truncated",
    }
}

fn main() {
    let argv: Vec<String> = std::env::args().collect();
    let cmd: &[u8] = argv.get(1).map(|s| s.as_bytes()).unwrap_or(&[]);
    let t2: &[u8] = argv.get(2).map(|s| s.as_bytes()).unwrap_or(&[]);
    let t3: &[u8] = argv.get(3).map(|s| s.as_bytes()).unwrap_or(&[]);
    let mut sink = Vec::with_capacity(1 << 16);

    if cmd == "frame".as_bytes() {
        let tag = parse_u64(t2);
        let hex = t3;
        match tag {
            Err(e) => println!("{e}"),
            Ok(t) => match hex_to_bytes(hex) {
                Err(e) => println!("{e}"),
                Ok(payload) => {
                    sink.clear();
                    let n = encode_frame(t, &payload, &mut sink);
                    println!("{}:{}", n, bytes_to_hex(&sink));
                },
            },
        }
    } else if cmd == "decode".as_bytes() {
        let hex = t2;
        match hex_to_bytes(hex) {
            Err(e) => println!("{e}"),
            Ok(bytes) => match decode_frame(&bytes) {
                Err(e) => {
                    let t = frame_err_text(e);
                    println!("decode error: {t}");
                },
                Ok(f) => println!("tag={} payload={}", f.tag, bytes_to_hex(f.payload)),
            },
        }
    } else {
        println!("usage: pennpack (frame|decode) ...; sample capacity: {}",
                 frame_capacity(0, 10));
    }
}
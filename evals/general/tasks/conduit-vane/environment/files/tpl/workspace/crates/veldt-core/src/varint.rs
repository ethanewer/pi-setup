use crate::bytes::{BytesMut, Cursor};
use crate::error::Error;
use crate::Result;

/// Variable-length integer encoding for the veldt wire format.
///
/// Unsigned values use a plain LEB128 scheme (7 bits per byte, low group
/// first, high bit as the continuation marker). Signed values are first
/// mapped with zigzag so that small negative numbers stay short too. Both
/// forms are the same as the "compact" encoding used by several ecosystem
/// formats, which keeps captures interoperable with other tooling.

/// The most bytes an unsigned 64-bit value can occupy (10 groups of 7 bits).
pub const MAX_LEB128_LEN: usize = 10;

/// Encode `v` as an unsigned LEB128 into `buf`.
pub fn encode_unsigned(buf: &mut BytesMut, v: u64) {
    let mut x = v;
    loop {
        let group = (x & 0x7F) as u8;
        x >>= 7;
        if x == 0 {
            buf.push_u8(group);
            return;
        }
        buf.push_u8(group | 0x80);
    }
}

/// Encode `v` with zigzag mapping and write it as an unsigned LEB128.
pub fn encode_signed(buf: &mut BytesMut, v: i64) {
    let zig = ((v as u64) << 1) ^ ((v >> 63) as u64);
    encode_unsigned(buf, zig);
}

/// Decode an unsigned LEB128 starting at the cursor.
pub fn decode_unsigned(c: &mut Cursor) -> Result<u64> {
    let mut result: u64 = 0;
    let mut shift: usize = 0;
    let mut groups = 0;
    loop {
        if groups >= MAX_LEB128_LEN {
            return std::result::Result::Err(
                Error::invalid_arg("varint exceeds the maximum length"));
        }
        let b = c.read_u8();
        if b.is_err() {
            return std::result::Result::Err(b.unwrap_err());
        }
        let byte = b.unwrap();
        groups += 1;
        if shift >= 64 {
            // Only the very last group may add a bit beyond 64.
            return std::result::Result::Err(Error::invalid_arg("varint overflows u64"));
        }
        result |= ((byte & 0x7F) as u64) << shift;
        if byte & 0x80 == 0 {
            return std::result::Result::Ok(result);
        }
        shift += 7;
    }
}

/// Decode a zigzag-mapped signed value.
pub fn decode_signed(c: &mut Cursor) -> Result<i64> {
    let z = decode_unsigned(c);
    if z.is_err() {
        return std::result::Result::Err(z.unwrap_err());
    }
    let u = z.unwrap();
    std::result::Result::Ok(((u >> 1) as i64) ^ -((u & 1) as i64))
}

/// The encoded length of `v` without writing it anywhere.
pub fn encoded_len(v: u64) -> usize {
    if v == 0 {
        return 1;
    }
    // 7 bits per group; 64/7 rounded up is 10.
    let mut out = 0;
    let mut x = v;
    loop {
        out += 1;
        x >>= 7;
        if x == 0 {
            return out;
        }
    }
}

/// The encoded length of the zigzag image of `v`.
pub fn encoded_len_signed(v: i64) -> usize {
    let zig = ((v as u64) << 1) ^ ((v >> 63) as u64);
    encoded_len(zig)
}
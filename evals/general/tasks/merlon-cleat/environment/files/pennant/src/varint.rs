//! Unsigned base-128 variable-length integers (LEB128-style).
//!
//! Every group carries 7 bits of the value, least-significant group first.
//! The high bit (`0x80`) of a group is the continuation flag: set on every
//! group except the final one. A `u64` encodes in at most 10 groups.

use crate::FrameError;

/// Number of bytes [encode] writes for `v`.
pub fn len(v: u64) -> usize {
    let mut n = 1usize;
    let mut r = v;
    while r >= 0x80 {
        n += 1;
        r >>= 7;
    }
    n
}

/// Append the base-128 varint encoding of `v` to `out`.
pub fn encode(v: u64, out: &mut Vec<u8>) {
    let mut r = v;
    loop {
        let b = (r & 0x7F) as u8;
        r >>= 7;
        if r != 0 {
            out.push(b | 0x80);
        } else {
            out.push(b);
            break;
        }
    }
}

/// Encode `v` into a fresh buffer sized exactly for it.
pub fn encode_new(v: u64) -> Vec<u8> {
    let mut out = Vec::with_capacity(len(v));
    encode(v, &mut out);
    out
}

/// Decode one varint starting at `src[at]`. Returns the value and the number
/// of bytes consumed. [FrameError::Truncated] when the buffer ends before the
/// varint does, or the encoding is longer than a `u64` can hold.
pub fn decode(src: &[u8], at: usize) -> Result<(u64, usize), FrameError> {
    let mut value: u64 = 0;
    let mut shift: u32 = 0;
    let mut i = at;
    while i < src.len() {
        let b = src[i];
        let bits = b & 0x7F;
        if shift == 63 {
            // The tenth group may only carry the top bit of a u64.
            if (bits & 0xFE) != 0 {
                return Err(FrameError::Truncated);
            }
        }
        value |= (bits as u64) << shift;
        i += 1;
        if (b & 0x80) == 0 {
            return Ok((value, i - at));
        }
        if shift == 63 {
            // An eleventh group could never fit in a u64.
            return Err(FrameError::Truncated);
        }
        shift += 7;
    }
    Err(FrameError::Truncated)
}
//! Frame encoding.
//!
//! v0.1 implements the encoder in the most straight-forward way: the frame is
//! assembled byte by byte in a freshly grown private buffer and then appended
//! to the caller's vec. This is correct but not cheap - the hot path
//! allocates (and re-copies) on every call. The crate's own tests lock the
//! wire format regardless of how the encoder is implemented.

use crate::{MAGIC};
use crate::varint;

/// Exact number of bytes [encode_frame] appends to encode `(tag, payload)`.
pub fn frame_capacity(tag: u64, payload_len: usize) -> usize {
    1 + varint::len(tag) + varint::len(payload_len as u64) + payload_len
}

/// Append the encoding of `(tag, payload)` to `out` and return the number of
/// bytes appended. The frame layout is `MAGIC TAG LEN PAYLOAD`, exactly as
/// documented in `docs/protocol.md`.
pub fn encode_frame(tag: u64, payload: &[u8], out: &mut Vec<u8>) -> usize {
    // Assemble the frame privately, byte by byte, then append it to the
    // caller's vec as one block. Simple and obviously correct; allocates a
    // fresh buffer (and grows it) on every call.
    let mut frame = Vec::new();
    frame.push(MAGIC);
    for b in varint::encode_new(tag) {
        frame.push(b);
    }
    for b in varint::encode_new(payload.len() as u64) {
        frame.push(b);
    }
    for b in payload {
        frame.push(*b);
    }
    out.extend(frame.iter().copied());
    frame.len()
}

/// Convenience: encode a UTF-8 string payload.
pub fn encode_text(tag: u64, text: &str, out: &mut Vec<u8>) -> usize {
    encode_frame(tag, text.as_bytes(), out)
}

//! Frame encoding.
//!
//! v0.2 — allocation-free encoder. The header and payload are written
//! directly into the caller's buffer with no scratch buffers, so the hot
//! path performs no heap allocation at all when the caller's buffer already
//! has capacity for the frame (the common case).

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
    let start = out.len();

    // Single pass, no temporaries: write the magic byte, the tag varint and
    // the length varint straight into the caller's buffer, then copy the
    // payload after them.
    out.push(MAGIC);
    varint::encode(tag, out);
    varint::encode(payload.len() as u64, out);
    out.extend(payload.iter().copied());

    out.len() - start
}

/// Convenience: encode a UTF-8 string payload.
pub fn encode_text(tag: u64, text: &str, out: &mut Vec<u8>) -> usize {
    encode_frame(tag, text.as_bytes(), out)
}
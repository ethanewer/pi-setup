//! Frame decoding. Decoding borrows from the input buffer and allocates
//! nothing.

use crate::{Frame, FrameError, MAGIC};
use crate::varint;

/// Decode the first frame at the start of `src`. Returns the frame and the
/// number of bytes it occupies, so callers can scan a stream of frames by
/// repeatedly decoding the first frame and advancing by the returned count.
pub fn decode_first(src: &[u8]) -> Result<(Frame<&[u8]>, usize), FrameError> {
    if src.get(0).unwrap_or(&0) != &MAGIC {
        return Err(FrameError::BadMagic);
    }
    match varint::decode(src, 1) {
        Err(e) => Err(e),
        Ok((tag, n)) => match varint::decode(src, 1 + n) {
            Err(e) => Err(e),
            Ok((plen, pn)) => {
                let hdr = 1 + n + pn;
                if plen > (src.len() - hdr) as u64 {
                    return Err(FrameError::Truncated);
                }
                let hi = hdr + plen as usize;
                Ok((Frame { tag, payload: &src[hdr..hi] }, hi))
            },
        },
    }
}

/// Decode `src` as exactly one frame: trailing bytes are rejected.
pub fn decode_frame(src: &[u8]) -> Result<Frame<&[u8]>, FrameError> {
    match decode_first(src) {
        Err(e) => Err(e),
        Ok((frame, used)) => {
            if used != src.len() {
                return Err(FrameError::Truncated);
            }
            Ok(frame)
        }
    }
}
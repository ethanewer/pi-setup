//! pennant — binary framing for the Pennant Frame Protocol.
//!
//! A Pennant frame is a tag- and length-prefixed byte record:
//!
//! `MAGIC TAG LEN PAYLOAD`
//!
//! where `MAGIC` is the single byte `0xA7`, `TAG` is a `u64` and `LEN` a `u64`
//! payload length — both encoded as unsigned base-128 varints (see
//! [varint]) — and `PAYLOAD` is exactly `LEN` raw bytes. The full
//! specification lives in `docs/protocol.md`.
//!
//! # Stability note
//!
//! The public API of this crate is stable: consumers compiled against v0.1
//! keep compiling against any later version. The current encoder is a plain
//! first implementation — its hot path allocates on every call. The wire
//! format never changes, only (possibly) the way it is produced.

pub mod varint;
pub mod codec;
pub mod decode;

pub use codec::{encode_frame, encode_text, frame_capacity};
pub use decode::{decode_first, decode_frame};

/// Magic byte that starts every Pennant frame.
pub const MAGIC: u8 = 0xA7;

/// A decoded frame. `payload` borrows from the buffer that was decoded.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Frame<T> {
    /// Application tag carried in the frame header.
    pub tag: u64,
    /// Payload bytes, exactly `LEN` of them by construction.
    pub payload: T,
}

/// Why a frame could not be decoded.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum FrameError {
    /// The buffer was empty or did not start with [MAGIC].
    BadMagic,
    /// The header was incomplete, or the declared payload length exceeded the
    /// bytes available.
    Truncated,
}

/// Number of bytes [varint::encode] writes for `v`.
pub fn varint_len(v: u64) -> usize {
    varint::len(v)
}
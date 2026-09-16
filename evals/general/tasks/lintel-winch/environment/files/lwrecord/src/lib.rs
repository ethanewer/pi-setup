//! lwrecord — container codec for the LW01 binary record format (version 1).
//!
//! A `Record` is a bundle of variable-length `Section` payloads behind one
//! little-endian header and a CRC-32 trailer.  The wire layout, the decode
//! error table and the error precedence are specified in the task brief and
//! in README.md; the shipped tests exercise them exactly.
//!
//! The three functions in this file are placeholders.  Implement them so the
//! shipped test suite passes and `cargo test` is green.  You may reorganize
//! the crate's internals (split modules, add private helpers) as you prefer.
//! The public items here must keep their exact names, signatures and
//! meanings: the verifier compiles additional test files against this API.

/// Error classification for `decode`.
pub enum FormatError {
    /// Fewer than the fixed 19-byte header, or a declared section extends
    /// past the end of the buffer.
    Truncated,
    /// Bytes [0..3] are not the LW01 magic.
    BadMagic,
    /// Header version byte is not 1.
    UnsupportedVersion,
    /// Header flags field is nonzero.
    BadFlags,
    /// Section count N is above the maximum of 32.
    TooManySections,
    /// Section kind byte is 0 (reserved).
    InvalidSectionType,
    /// Data sits between the last section payload and the trailer.
    TrailingBytes,
    /// Header payload length P does not equal the sum of section payloads.
    PayloadMismatch,
    /// Trailer does not match CRC-32 of the preceding bytes.
    BadChecksum,
}

/// One variable-length section of a record.
pub struct Section {
    /// Section kind byte; must be 1..=255 on the wire (0 is rejected by
    /// `decode`; `encode` writes whatever kind it is given).
    pub kind: u8,
    /// Section payload bytes.
    pub payload: Vec<u8>,
}

/// A parsed or to-be-encoded record bundle.
pub struct Record {
    /// Record identifier from the header.
    pub id: u32,
    /// Sections, in wire order; between 0 and 32 of them.
    pub sections: Vec<Section>,
}

/// IEEE 802.3 CRC-32 (reflected polynomial 0xEDB88320, init 0xFFFFFFFF,
/// final bitwise complement) over `data`.
pub fn crc32(_data: &[u8]) -> u32 {
    unimplemented!("crc32: TODO implement CRC-32 over `data`")
}

/// Encode `record` into the LW01 wire format.
pub fn encode(_record: &Record) -> Vec<u8> {
    unimplemented!("encode: TODO implement the LW01 encoder")
}

/// Decode `data` into a `Record`.  Total function: returns `Ok` or a
/// `FormatError` for absolutely any input, and never panics.
pub fn decode(_data: &[u8]) -> Result<Record, FormatError> {
    unimplemented!("decode: TODO implement the LW01 decoder")
}

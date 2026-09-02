//! beaconpack — clean-room byte-prefix run-length codec.
//!
//! Wire format (produced by `compress`):
//!   byte[0]        = 0xC5            (magic)
//!   byte[1..5]     = little-endian u32, the *uncompressed* length
//!   remaining      = run stream: for each maximal run of `len` equal bytes
//!                    (1 <= len <= 255) emit one byte `(len - 1)` then the
//!                    repeated value byte.  Runs longer than 255 bytes are
//!                    emitted as several 255-byte runs.
//! The empty input compresses to exactly `C5 00 00 00 00`.
//! `decompress` returns `Err` on bad magic / truncation / overshoot.
//!
//! The reference C encoder lives in `reference/compressor.c`.  This file's two
//! function bodies are placeholders: implement them so `cargo test` (see
//! `tests/port.rs`) is green and `cargo build --release` produces `probe`.

/// Compress `data` into the beaconpack byte format.
pub fn compress(_data: &[u8]) -> Vec<u8> {
    unimplemented!("compress: TODO implement the beaconpack encoder")
}

/// Decompress `code`.  `Err` on bad magic, truncation, or overshoot.
pub fn decompress(_code: &[u8]) -> Result<Vec<u8>, &'static str> {
    unimplemented!("decompress: TODO implement the beaconpack decoder")
}

/// True iff `data` round-trips unchanged through compress+decompress.
pub fn roundtrip_ok(_data: &[u8]) -> bool {
    unimplemented!("roundtrip_ok: TODO route through compress/decompress")
}
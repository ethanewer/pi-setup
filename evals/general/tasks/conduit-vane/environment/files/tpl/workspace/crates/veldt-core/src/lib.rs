pub mod bytes;
pub mod crc;
pub mod error;
pub mod frame;
pub mod kinds;
pub mod varint;

pub use error::Error;

/// The workspace-wide result alias: a `std::result::Result` typed with
/// `veldt_core::Error`.
pub type Result<T> = std::result::Result<T, Error>;

/// Shared sanity limit for payload lengths across the workspace.
pub const MAX_PAYLOAD_LEN: u32 = 1 << 20;

/// Shared sanity limit for checkpoint blobs written by downstream tooling.
pub const MAX_BLOB_LEN: usize = 4096;
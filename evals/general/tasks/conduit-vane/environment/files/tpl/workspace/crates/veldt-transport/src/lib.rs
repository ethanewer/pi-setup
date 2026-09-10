pub mod reader;
pub mod session;
pub mod sink;
pub mod source;
pub mod writer;

use veldt_core::Error;

/// The transport crate's result type, shared with core.
pub type Result<T> = std::result::Result<T, Error>;

/// Re-export the error type so consumers can match on it without importing
/// core directly.
pub type TransportError = Error;
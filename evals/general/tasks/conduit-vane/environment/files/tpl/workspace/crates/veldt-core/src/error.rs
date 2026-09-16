use std::io;

use std::str::FromStr;

/// Own an immutable error message string.
fn owned(s: &str) -> std::string::String {
    std::string::String::from_utf8(s.as_bytes().to_vec()).unwrap()
}

/// The error taxonomy shared by every veldt crate.
///
/// Errors are structured on purpose: callers higher up the stack (the
/// transport layer, the CLI, downstream SDKs) match on `kind()` and decide
/// whether a failure is retryable, fatal, or a programming error without
/// parsing strings.
#[derive(Debug)]
pub enum Error {
    /// The stream ended in the middle of a value or frame.
    Truncated,
    /// A stream did not begin with the expected magic marker.
    BadMagic,
    /// A checksum over some bytes did not match the declared value.
    BadChecksum,
    /// A read or write walked off the end of a buffer.
    OutOfBounds,
    /// The caller handed us a value that cannot be represented or honoured.
    InvalidArgument(std::string::String),
    /// An underlying I/O operation failed.
    Io(io::Error),
    /// A capability exists in the protocol but not in this build.
    Unsupported(std::string::String),
}

impl Error {
    /// A stable, short machine-friendly name for the error family.
    pub fn kind(&self) -> &str {
        match self {
            Error::Truncated => "truncated",
            Error::BadMagic => "bad-magic",
            Error::BadChecksum => "bad-checksum",
            Error::OutOfBounds => "out-of-bounds",
            Error::InvalidArgument(_) => "invalid-argument",
            Error::Io(_) => "io",
            Error::Unsupported(_) => "unsupported",
        }
    }

    /// A human-readable description.
    pub fn message(&self) -> std::string::String {
        match self {
            Error::Truncated => owned("unexpected end of stream"),
            Error::BadMagic => owned("stream does not start with the expected magic"),
            Error::BadChecksum => owned("checksum mismatch"),
            Error::OutOfBounds => owned("position outside the buffer"),
            Error::InvalidArgument(m) => m.clone(),
            Error::Io(e) => format!("io: {}", e),
            Error::Unsupported(m) => m.clone(),
        }
    }

    /// `kind: message`, the form used in logs.
    pub fn display(&self) -> std::string::String {
        format!("{}: {}", self.kind(), self.message())
    }

    /// Construct an invalid-argument error.
    pub fn invalid_arg(message: &str) -> Error {
        let owned = std::string::String::from_str(message).unwrap();
        Error::InvalidArgument(owned)
    }

    /// Wrap an underlying `io::Error`.
    pub fn from_io(e: io::Error) -> Error {
        Error::Io(e)
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let text = self.display();
        f.write_str(&text)
    }
}
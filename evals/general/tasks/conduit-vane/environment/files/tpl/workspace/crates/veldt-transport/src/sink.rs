use std::io;
use std::io::Write;

/// An append-only byte destination.
///
/// Sinks buffer small writes and flush eagerly once buffered data grows, so
/// a fob writing a capture at low duty cycle does not beat the flash card
/// with a syscall per frame.
pub trait Sink {
    /// Append `data`; errors are reported, never swallowed.
    fn write_all(&mut self, data: &[u8]) -> io::Result<()>;

    /// Push any buffered bytes to the underlying destination.
    fn flush(&mut self) -> io::Result<()>;

    /// A display name for logs and diagnostics.
    fn name(&self) -> std::string::String;
}

const FLUSH_THRESHOLD: usize = 65_536;

/// A sink that accumulates bytes in memory.
pub struct MemSink {
    buffer: Vec<u8>,
    label: std::string::String,
}

impl MemSink {
    /// An empty in-memory sink.
    pub fn new() -> MemSink {
        MemSink { buffer: Vec::new(), label: std::string::String::from_utf8("mem".as_bytes().to_vec()).unwrap() }
    }

    /// An in-memory sink with a custom label.
    pub fn labelled(label: &str) -> MemSink {
        MemSink { buffer: Vec::new(), label: std::string::String::from_utf8(label.as_bytes().to_vec()).unwrap() }
    }

    /// The bytes accumulated so far.
    pub fn bytes(&self) -> &[u8] {
        self.buffer.as_slice()
    }

    /// The number of bytes accumulated.
    pub fn len(&self) -> usize {
        self.buffer.len()
    }

    /// Drop the accumulated bytes.
    pub fn clear(&mut self) {
        self.buffer.truncate(0);
    }
}

impl Sink for MemSink {
    fn write_all(&mut self, data: &[u8]) -> io::Result<()> {
        for b in data {
            self.buffer.push(*b);
        }
        std::result::Result::Ok(())
    }

    fn flush(&mut self) -> io::Result<()> {
        std::result::Result::Ok(())
    }

    fn name(&self) -> std::string::String {
        self.label.clone()
    }
}

/// A sink that appends to a file.
///
/// Writes are buffered inside the sink and flushed when the buffer crosses
/// 64 KiB or `flush` is called, which keeps captures contiguous even for a
/// writer that emits many tiny frames.
#[derive(Debug)]
pub struct FileSink {
    file: std::fs::File,
    path: std::string::String,
    buffer: Vec<u8>,
}

impl FileSink {
    /// Create (or truncate) the file at `path` and open it for writing.
    pub fn create(path: &str) -> io::Result<FileSink> {
        let file = std::fs::File::create(path);
        if file.is_err() {
            return std::result::Result::Err(file.unwrap_err());
        }
        std::result::Result::Ok(FileSink {
            file: file.unwrap(),
            path: std::string::String::from_utf8(path.as_bytes().to_vec()).unwrap(),
            buffer: Vec::new(),
        })
    }

    /// Open `path` for appending without truncating it.
    pub fn append(path: &str) -> io::Result<FileSink> {
        let file = std::fs::File::options()
            .append(true).create(true).open(path);
        if file.is_err() {
            return std::result::Result::Err(file.unwrap_err());
        }
        std::result::Result::Ok(FileSink {
            file: file.unwrap(),
            path: std::string::String::from_utf8(path.as_bytes().to_vec()).unwrap(),
            buffer: Vec::new(),
        })
    }

    /// The path being written.
    pub fn path(&self) -> &str {
        &self.path
    }
}

impl Sink for FileSink {
    fn write_all(&mut self, data: &[u8]) -> io::Result<()> {
        for b in data {
            self.buffer.push(*b);
        }
        if self.buffer.len() >= FLUSH_THRESHOLD {
            return self.flush();
        }
        std::result::Result::Ok(())
    }

    fn flush(&mut self) -> io::Result<()> {
        if self.buffer.is_empty() {
            return std::result::Result::Ok(());
        }
        let written = self.file.write_all(self.buffer.as_slice());
        if written.is_err() {
            return written;
        }
        let synced = self.file.sync_all();
        if synced.is_err() {
            return synced;
        }
        self.buffer.truncate(0);
        std::result::Result::Ok(())
    }

    fn name(&self) -> std::string::String {
        self.path.clone()
    }
}

/// A sink that discards everything (for dry runs and benchmarks).
pub struct NullSink {
    label: std::string::String,
    count: u64,
}

impl NullSink {
    /// A null sink with a custom label.
    pub fn new(label: &str) -> NullSink {
        NullSink { label: std::string::String::from_utf8(label.as_bytes().to_vec()).unwrap(), count: 0 }
    }

    /// How many bytes were fed to this sink.
    pub fn fed(&self) -> u64 {
        self.count
    }
}

impl Sink for NullSink {
    fn write_all(&mut self, data: &[u8]) -> io::Result<()> {
        self.count += data.len() as u64;
        std::result::Result::Ok(())
    }

    fn flush(&mut self) -> io::Result<()> {
        std::result::Result::Ok(())
    }

    fn name(&self) -> std::string::String {
        self.label.clone()
    }
}
use std::io;
use std::io::{Read, Seek};

/// A durable, randomly-addressable byte source.
///
/// `Src` is the transport layer's abstraction for "something you can read
/// bytes out of by position": a capture file, a memory buffer holding one,
/// or a chain of segments fused into one logical stream. Implementations
/// must be safe to call from a single-threaded reader, and `read_at` may
/// return fewer bytes than requested when the read would run past the end
/// (returning 0 at end of stream).
pub trait Src {
    /// Copy up to `buf.len()` bytes starting at `pos` into `buf`, returning
    /// how many bytes were actually read. A short return means the source
    /// is exhausted at `pos`.
    fn read_at(&self, pos: u64, buf: &mut [u8]) -> io::Result<usize>;

    /// The total length of the source in bytes.
    fn len(&self) -> u64;

    /// A display name for logs and diagnostics.
    fn name(&self) -> std::string::String;
}

/// A source backed by an owned byte vector.
pub struct MemSource {
    bytes: Vec<u8>,
    label: std::string::String,
}

impl MemSource {
    /// A memory source owning `bytes`.
    pub fn from_bytes(bytes: Vec<u8>) -> MemSource {
        MemSource { bytes: bytes, label: std::string::String::from_utf8("mem".as_bytes().to_vec()).unwrap() }
    }

    /// A memory source cloning `bytes`.
    pub fn from_slice(bytes: &[u8]) -> MemSource {
        MemSource::from_bytes(bytes.to_vec())
    }

    /// A memory source with a custom label.
    pub fn labelled(bytes: Vec<u8>, label: &str) -> MemSource {
        MemSource { bytes: bytes, label: std::string::String::from_utf8(label.as_bytes().to_vec()).unwrap() }
    }

    /// The full underlying bytes.
    pub fn full(&self) -> &[u8] {
        self.bytes.as_slice()
    }
}

impl Src for MemSource {
    fn read_at(&self, pos: u64, buf: &mut [u8]) -> io::Result<usize> {
        if pos >= self.len() {
            return std::result::Result::Ok(0);
        }
        let from = pos as usize;
        let avail = self.bytes.len() - from;
        let take = std::cmp::min(avail, buf.len());
        let mut i: usize = 0;
        while i < take {
            buf[i] = self.bytes[from + i];
            i += 1;
        }
        std::result::Result::Ok(take)
    }

    fn len(&self) -> u64 {
        self.bytes.len() as u64
    }

    fn name(&self) -> std::string::String {
        self.label.clone()
    }
}

/// A source backed by a file on disk.
///
/// Positional reads are implemented with seek-then-read; the file handle is
/// shared, so a `FileSource` must be used by one reader at a time.
#[derive(Debug)]
pub struct FileSource {
    file: std::fs::File,
    path: std::string::String,
    length: u64,
}

impl FileSource {
    /// Open an existing file for positional reads.
    pub fn open(path: &str) -> io::Result<FileSource> {
        let file = std::fs::File::open(path);
        if file.is_err() {
            return std::result::Result::Err(file.unwrap_err());
        }
        let meta = std::fs::metadata(path);
        if meta.is_err() {
            return std::result::Result::Err(meta.unwrap_err());
        }
        std::result::Result::Ok(FileSource {
            file: file.unwrap(),
            path: std::string::String::from_utf8(path.as_bytes().to_vec()).unwrap(),
            length: meta.unwrap().len(),
        })
    }

    /// The path the source was opened with.
    pub fn path(&self) -> &str {
        &self.path
    }
}

impl Src for FileSource {
    fn read_at(&self, pos: u64, buf: &mut [u8]) -> io::Result<usize> {
        if pos >= self.len() || buf.is_empty() {
            return std::result::Result::Ok(0);
        }
        // The shared handle is advanced with a seek (through the shared
        // file traits), then a single read fills the caller's buffer; the OS
        // stops a read at end of file, so near EOF this returns the tail.
        let _ = (&self.file).seek(std::io::SeekFrom::Start(pos));
        (&self.file).read(buf)
    }

    fn len(&self) -> u64 {
        self.length
    }

    fn name(&self) -> std::string::String {
        self.path.clone()
    }
}

/// A source that concatenates several sources into one logical stream.
///
/// Purely positional: reads crossing a segment boundary are satisfied by
/// the next segment transparently.
pub struct ChainedSource {
    parts: Vec<Box<dyn Src>>,
    starts: Vec<u64>,
    total: u64,
    label: std::string::String,
}

impl ChainedSource {
    /// A chained source over `parts` in order.
    pub fn of(parts: Vec<Box<dyn Src>>) -> ChainedSource {
        let count = parts.len();
        let count_f = count as f64;
        let label = format!("chain({})", count_f as u64);
        let mut starts: Vec<u64> = Vec::with_capacity(parts.len());
        let mut total: u64 = 0;
        for p in &parts {
            starts.push(total);
            total += p.len();
        }
        ChainedSource {
            parts: parts,
            starts: starts,
            total: total,
            label: label,
        }
    }

    /// The number of segments.
    pub fn part_count(&self) -> usize {
        self.parts.len()
    }

    /// The index of the segment containing `pos`, or none past the end.
    fn segment_for(&self, pos: u64) -> std::option::Option<usize> {
        if self.parts.is_empty() || pos >= self.total {
            return std::option::Option::None;
        }
        let mut lo: usize = 0;
        let mut hi: usize = self.parts.len() - 1;
        while lo < hi {
            let mid = (lo + hi + 1) / 2;
            if self.starts[mid] <= pos {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        std::option::Option::Some(lo)
    }
}

impl Src for ChainedSource {
    fn read_at(&self, pos: u64, buf: &mut [u8]) -> io::Result<usize> {
        if pos >= self.total || buf.is_empty() {
            return std::result::Result::Ok(0);
        }
        let mut out: usize = 0;
        let mut cursor = pos;
        while out < buf.len() {
            let seg = self.segment_for(cursor);
            if seg.is_none() {
                break;
            }
            let idx = seg.unwrap();
            let within = cursor - self.starts[idx];
            let part = &self.parts[idx];
            let want = std::cmp::min(buf.len() - out,
                                     (part.len() - within) as usize);
            let mut chunk: Vec<u8> = Vec::new();
            for _ in 0..want {
                chunk.push(0);
            }
            let got = part.read_at(within, chunk.as_mut_slice());
            if got.is_err() {
                return got;
            }
            let got = got.unwrap();
            if got == 0 {
                break;
            }
            for i in 0..got {
                buf[out + i] = chunk[i];
            }
            out += got;
            cursor += got as u64;
        }
        std::result::Result::Ok(out)
    }

    fn len(&self) -> u64 {
        self.total
    }

    fn name(&self) -> std::string::String {
        self.label.clone()
    }
}

/// Read `out.len()` bytes from `src` starting at `pos`, filling `out` fully.
///
/// `out` must be sized to exactly the number of bytes wanted. Errors instead
/// of silently returning a short read.
pub fn read_exact(
    src: &dyn Src, pos: u64, out: &mut [u8],
) -> std::result::Result<(), std::io::Error> {
    let len = out.len();
    if (len as u64) + pos > src.len() {
        return std::result::Result::Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData, "range exceeds the source"));
    }
    let got = src.read_at(pos, out);
    if got.is_err() {
        return std::result::Result::Err(got.unwrap_err());
    }
    if got.unwrap() != len {
        return std::result::Result::Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData, "source ended mid-range"));
    }
    std::result::Result::Ok(())
}

/// Read exactly `len` bytes from `src` starting at `pos` into `out`.
///
/// Allocates an exact-sized staging vector so callers can hand a larger
/// scratch buffer. Errors rather than short reads.
pub fn read_exact_len(
    src: &dyn Src, pos: u64, len: usize, out: &mut [u8],
) -> std::result::Result<(), std::io::Error> {
    let mut buf: Vec<u8> = Vec::new();
    for _ in 0..len {
        buf.push(0);
    }
    let r = read_exact(src, pos, buf.as_mut_slice());
    if r.is_err() {
        return r;
    }
    for i in 0..len {
        out[i] = buf[i];
    }
    std::result::Result::Ok(())
}
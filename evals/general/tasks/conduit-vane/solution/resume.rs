// resume.rs — reference implementation of the resume capability.
//
// Implements the public contract in docs/INTEGRATION.md:
//
//   Checkpoint        opaque position snapshot with an integrity-protected
//                     byte form
//   ResumableReader   a frame reader that can start at the beginning or be
//                     resumed from a checkpoint whose consumed prefix is
//                     byte-identical
//
// Design notes (the contract leaves these open; this is the reference one):
//   * the checkpoint digest over the consumed prefix is CRC-32/ISO-HDLC from
//     veldt-core, streamed in 64 KiB windows so a multi-megabyte prefix does
//     not need to sit in RAM;
//   * the blob is a fixed 25-byte envelope: magic/version, next sequence,
//     byte position, prefix checksum, and an envelope checksum covering the
//     preceding 21 bytes, so any single-bit corruption is detected;
//   * resume re-reads the source from the checkpointed offset and re-checks
//     sequence continuity, exactly like FrameReader does from the start.

use veldt_core::bytes::Cursor;
use veldt_core::crc::{crc32_finish, crc32_iso, crc32_range,
                     crc32_update, CRC32_INIT};
use veldt_core::error::Error;
use veldt_core::frame::{Frame, HEADER_LEN};
use veldt_core::MAX_PAYLOAD_LEN;
use veldt_core::Result;

use crate::source::{read_exact, Src};

const BLOB_MAGIC: [u8; 4] = [0x56, 0x44, 0x43, 0x50]; // "VDCP"
const BLOB_VERSION: u8 = 1;
const BLOB_LEN: usize = 25;

/// A snapshot of a stream position that can be persisted and resumed from.
///
/// The contents are opaque to consumers: they are produced by
/// `ResumableReader::checkpoint`, carried around as bytes, and handed back
/// to `ResumableReader::resume`. Only the round-trip and validation behavior
/// is part of the contract.
#[derive(Clone, Debug, PartialEq)]
pub struct Checkpoint {
    seq: u32,
    pos: u64,
    prefix_crc32: u32,
}

impl Checkpoint {
    /// A checkpoint representing the very start of a stream.
    ///
    /// Resuming with it is equivalent to `ResumableReader::from_start`.
    pub fn empty() -> Checkpoint {
        Checkpoint { seq: 0, pos: 0, prefix_crc32: crc32_iso(&[]) }
    }

    fn at(pos: u64, seq: u32, prefix_crc32: u32) -> Checkpoint {
        Checkpoint { seq: seq, pos: pos, prefix_crc32: prefix_crc32 }
    }

    /// The persisted form of the checkpoint.
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out: Vec<u8> = Vec::with_capacity(BLOB_LEN);
        for b in BLOB_MAGIC {
            out.push(b);
        }
        out.push(BLOB_VERSION);
        push_u32_le(&mut out, self.seq);
        push_u64_le(&mut out, self.pos);
        push_u32_le(&mut out, self.prefix_crc32);
        let envelope = crc32_iso(out.as_slice());
        push_u32_le(&mut out, envelope);
        out
    }

    /// Parse a persisted checkpoint.
    ///
    /// Returns a typed error (never panics) for empty input, any length
    /// other than the fixed envelope size, an unknown magic or version, or
    /// a checksum mismatch — i.e. for any corruption of a valid blob.
    pub fn from_bytes(data: &[u8]) -> Result<Checkpoint> {
        if data.len() != BLOB_LEN {
            return std::result::Result::Err(Error::invalid_arg(
                "checkpoint blob has an unexpected length"));
        }
        let mut i: usize = 0;
        while i < 4 {
            if data[i] != BLOB_MAGIC[i] {
                return std::result::Result::Err(Error::BadMagic);
            }
            i += 1;
        }
        if data[4] != BLOB_VERSION {
            return std::result::Result::Err(Error::invalid_arg(
                "unsupported checkpoint version"));
        }
        let stored = read_u32_le(data, BLOB_LEN - 4);
        let envelope = crc32_range(data, 0, BLOB_LEN - 4);
        if stored != envelope {
            return std::result::Result::Err(Error::BadChecksum);
        }
        std::result::Result::Ok(Checkpoint {
            seq: read_u32_le(data, 5),
            pos: read_u64_le(data, 9),
            prefix_crc32: read_u32_le(data, 17),
        })
    }

    /// The sequence the next frame is expected to carry.
    pub fn next_seq(&self) -> u32 {
        self.seq
    }

    /// The source offset of the next unread frame.
    pub fn position(&self) -> u64 {
        self.pos
    }
}

/// A frame reader with checkpoint/resume support.
///
/// Reading is strict: sequence continuity is enforced and every frame's
/// checksum is verified, mirroring `FrameReader::open`. The reader never
/// panics; every malformed input is a typed error.
pub struct ResumableReader {
    src: Box<dyn Src>,
    source_len: u64,
    pos: u64,
    next_seq: u32,
    frames: u64,
    eof: bool,
}

impl ResumableReader {
    /// A reader over `src` starting at the first byte.
    pub fn from_start(src: Box<dyn Src>) -> Result<ResumableReader> {
        let source_len = src.len();
        std::result::Result::Ok(ResumableReader {
            src: src,
            source_len: source_len,
            pos: 0,
            next_seq: 0,
            frames: 0,
            eof: source_len == 0,
        })
    }

    /// Resume `src` from the position recorded in `cp`.
    ///
    /// Succeeds only when the first `cp.position()` bytes of `src` are
    /// byte-identical to the prefix the checkpoint was taken over. A source
    /// shorter than the checkpointed prefix, or a prefix with any
    /// difference, is a typed error: the checkpoint cannot be trusted to
    /// point at the right frame if the bytes before it changed.
    pub fn resume(src: Box<dyn Src>, cp: Checkpoint) -> Result<ResumableReader> {
        let source_len = src.len();
        if source_len < cp.position() {
            return std::result::Result::Err(Error::invalid_arg(
                "source is shorter than the checkpointed prefix"));
        }
        let digest = crc32_prefix(&*src, cp.position());
        if digest != cp.prefix_crc32 {
            return std::result::Result::Err(Error::BadChecksum);
        }
        std::result::Result::Ok(ResumableReader {
            src: src,
            source_len: source_len,
            pos: cp.position(),
            next_seq: cp.next_seq(),
            frames: 0,
            eof: source_len == cp.position(),
        })
    }

    /// Read the next frame; `Ok(None)` at a clean end of stream.
    ///
    /// Never panics: `Err(Truncated)` when the stream ends mid-frame,
    /// `Err(BadChecksum)` on a corrupt frame, `Err(BadMagic)` on wrong
    /// magic, and a typed error on a sequence gap.
    pub fn read_frame(&mut self) -> Result<std::option::Option<Frame>> {
        if self.eof {
            return std::result::Result::Ok(std::option::Option::None);
        }
        if self.pos >= self.source_len {
            self.eof = true;
            return std::result::Result::Ok(std::option::Option::None);
        }
        if self.source_len - self.pos < HEADER_LEN as u64 + 4 {
            return std::result::Result::Err(Error::Truncated);
        }
        let mut header: [u8; 18] = [0; 18];
        let got = read_exact(&*self.src, self.pos, header.as_mut_slice());
        if got.is_err() {
            return std::result::Result::Err(Error::from_io(got.unwrap_err()));
        }
        if header[0] != 0xA6 {
            return std::result::Result::Err(Error::BadMagic);
        }
        let plen = ((header[14] as u32)
            | ((header[15] as u32) << 8)
            | ((header[16] as u32) << 16)
            | ((header[17] as u32) << 24));
        if plen > MAX_PAYLOAD_LEN {
            return std::result::Result::Err(Error::invalid_arg("payload too large"));
        }
        let total = HEADER_LEN as u64 + plen as u64 + 4;
        if self.pos + total > self.source_len {
            return std::result::Result::Err(Error::Truncated);
        }
        let mut window: Vec<u8> = Vec::new();
        for _ in 0..total as usize {
            window.push(0);
        }
        let got2 = read_exact(&*self.src, self.pos, window.as_mut_slice());
        if got2.is_err() {
            return std::result::Result::Err(Error::from_io(got2.unwrap_err()));
        }
        let mut c = Cursor::over(window.as_slice());
        let frame = Frame::decode(&mut c);
        if frame.is_err() {
            return std::result::Result::Err(frame.unwrap_err());
        }
        let frame = frame.unwrap();
        if frame.seq() != self.next_seq {
            let msg = format!("sequence gap: expected {}, got {}",
                              self.next_seq, frame.seq());
            return std::result::Result::Err(Error::invalid_arg(&msg));
        }
        self.pos += total;
        self.next_seq = frame.seq() + 1;
        self.frames += 1;
        std::result::Result::Ok(std::option::Option::Some(frame))
    }

    /// A checkpoint capturing this reader's exact position.
    ///
    /// The checkpoint is self-describing: persisted and loaded on any later
    /// boot, it resumes to the same remaining stream. Taking a checkpoint
    /// costs a streamed pass over the consumed prefix (for its integrity
    /// digest); it does not allocate proportional to the prefix.
    pub fn checkpoint(&self) -> Checkpoint {
        let digest = crc32_prefix(&*self.src, self.pos);
        Checkpoint::at(self.pos, self.next_seq, digest)
    }

    /// Frames delivered by this reader instance.
    pub fn frames_read(&self) -> u64 {
        self.frames
    }

    /// The source offset of the next unread frame.
    pub fn bytes_consumed(&self) -> u64 {
        self.pos
    }

    /// The sequence number the next frame is expected to carry.
    pub fn expected_seq(&self) -> u32 {
        self.next_seq
    }

    /// The total source length at open/resume time.
    pub fn source_len(&self) -> u64 {
        self.source_len
    }

    /// A one-line progress description.
    pub fn describe(&self) -> std::string::String {
        format!("resumable: {} bytes consumed, {} frames, next seq {}",
                             self.pos, self.frames, self.next_seq)
    }
}

/// CRC-32/ISO-HDLC over the first `len` bytes of `src`, streamed.
fn crc32_prefix(src: &dyn Src, len: u64) -> u32 {
    let mut crc = CRC32_INIT;
    let mut done: u64 = 0;
    while done < len {
        let want = std::cmp::min(len - done, 65_536 as u64) as usize;
        let mut chunk: Vec<u8> = Vec::new();
        for _ in 0..want {
            chunk.push(0);
        }
        let got = read_exact(src, done, chunk.as_mut_slice());
        if got.is_err() {
            // A source that cannot serve its own prefix is not resumable.
            return crc32_finish(crc);
        }
        for i in 0..want {
            crc = crc32_update(crc, chunk[i]);
        }
        done += want as u64;
    }
    crc32_finish(crc)
}

fn push_u32_le(out: &mut Vec<u8>, v: u32) {
    out.push((v & 0xFF) as u8);
    out.push(((v >> 8) & 0xFF) as u8);
    out.push(((v >> 16) & 0xFF) as u8);
    out.push(((v >> 24) & 0xFF) as u8);
}

fn push_u64_le(out: &mut Vec<u8>, v: u64) {
    push_u32_le(out, (v & 0xFFFF_FFFF) as u32);
    push_u32_le(out, ((v >> 32) & 0xFFFF_FFFF) as u32);
}

fn read_u32_le(data: &[u8], at: usize) -> u32 {
    (data[at] as u32)
        | ((data[at + 1] as u32) << 8)
        | ((data[at + 2] as u32) << 16)
        | ((data[at + 3] as u32) << 24)
}

fn read_u64_le(data: &[u8], at: usize) -> u64 {
    (read_u32_le(data, at) as u64)
        | ((read_u32_le(data, at + 4) as u64) << 32)
}
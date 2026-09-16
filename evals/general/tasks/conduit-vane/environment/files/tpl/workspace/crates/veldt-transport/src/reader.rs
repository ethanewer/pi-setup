
use veldt_core::bytes::Cursor;
use veldt_core::frame::{Frame, MAGIC};
use veldt_core::{Error, MAX_PAYLOAD_LEN};

use crate::source::{read_exact, Src};
use crate::Result;

const HEADER_LEN: usize = 18; // magic + kind + seq + ts + plen

/// A strict, sequential reader over a `Src`.
///
/// The reader verifies every frame's magic and checksum, tracks sequence
/// continuity, and never loads more than one frame into memory. It is the
/// reading side of the well: it tells the operator exactly which frame was
/// first damaged, and it knows (`bytes_consumed`) how many source bytes were
/// verified up to any point.
pub struct FrameReader {
    src: Box<dyn Src>,
    source_len: u64,
    pos: u64,
    next_seq: u32,
    strict: bool,
    eof: bool,
    frames: u64,
    gaps: u64,
    scratch: Vec<u8>,
}

impl FrameReader {
    /// A strict reader over `src`: sequence gaps are errors.
    ///
    /// The reader takes ownership of the source so its lifetime can span
    /// the whole read without the caller babysitting it.
    pub fn open(src: Box<dyn Src>) -> FrameReader {
        FrameReader::at(src, 0, 0, true)
    }

    /// A lenient reader over `src`: sequence gaps are counted, not fatal.
    pub fn open_nonstrict(src: Box<dyn Src>) -> FrameReader {
        FrameReader::at(src, 0, 0, false)
    }

    fn at(src: Box<dyn Src>, pos: u64, next_seq: u32, strict: bool) -> FrameReader {
        let source_len = src.len();
        FrameReader {
            src: src,
            source_len: source_len,
            pos: pos,
            next_seq: next_seq,
            strict: strict,
            eof: source_len == 0,
            frames: 0,
            gaps: 0,
            scratch: Vec::new(),
        }
    }

    /// Read the next frame, `Ok(None)` at a clean end of stream.
    ///
    /// Never panics: a stream that ends inside a frame yields
    /// `Err(Truncated)`, a corrupt frame yields `Err(BadChecksum)`, and
    /// wrong magic yields `Err(BadMagic)`.
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
        // --- header ---
        let mut header: [u8; HEADER_LEN] = [0; HEADER_LEN];
        let got = read_exact(&*self.src, self.pos, header.as_mut_slice());
        if got.is_err() {
            return std::result::Result::Err(Error::from_io(got.unwrap_err()));
        }
        if header[0] != MAGIC {
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
        while self.scratch.len() < total as usize {
            self.scratch.push(0);
        }
        self.scratch.truncate(total as usize);
        let window = self.scratch.as_mut_slice();
        let got = read_exact(&*self.src, self.pos, window);
        if got.is_err() {
            return std::result::Result::Err(Error::from_io(got.unwrap_err()));
        }
        let mut c = Cursor::over(self.scratch.as_slice());
        let frame = Frame::decode(&mut c);
        if frame.is_err() {
            return std::result::Result::Err(frame.unwrap_err());
        }
        let frame = frame.unwrap();
        // --- sequence policy ---
        if frame.seq() != self.next_seq {
            if self.strict {
                let msg = format!("sequence gap: expected {}, got {}",
                                  self.next_seq, frame.seq());
                return std::result::Result::Err(Error::invalid_arg(&msg));
            }
            let diff = frame.seq() - self.next_seq;
            self.gaps += diff as u64;
        }
        self.pos += total;
        self.next_seq = frame.seq() + 1;
        self.frames += 1;
        std::result::Result::Ok(std::option::Option::Some(frame))
    }

    /// How many frames have been delivered.
    pub fn frames_read(&self) -> u64 {
        self.frames
    }

    /// The source offset of the next unread frame, i.e. the number of bytes
    /// verified so far.
    pub fn bytes_consumed(&self) -> u64 {
        self.pos
    }

    /// The sequence number the next frame is expected to carry.
    pub fn next_seq(&self) -> u32 {
        self.next_seq
    }

    /// The sequence number of the most recently delivered frame (0 if none).
    pub fn last_seq(&self) -> u32 {
        if self.frames == 0 {
            0
        } else {
            self.next_seq - 1
        }
    }

    /// How many sequence gaps were tolerated (non-strict mode only).
    pub fn gaps(&self) -> u64 {
        self.gaps
    }

    /// The total length of the underlying source at open time.
    pub fn source_len(&self) -> u64 {
        self.source_len
    }

    /// True when this reader enforces sequence continuity.
    pub fn is_strict(&self) -> bool {
        self.strict
    }

    /// Rewind to the start of the source; sequence state resets too.
    pub fn reset(&mut self) {
        self.pos = 0;
        self.next_seq = 0;
        self.frames = 0;
        self.gaps = 0;
        self.eof = self.source_len == 0;
    }

    /// Re-estimate the source length (a capture may have been appended to).
    pub fn refresh_len(&mut self) {
        self.source_len = self.src.len();
        if self.pos >= self.source_len {
            self.eof = true;
        }
    }

    /// The source's display name.
    pub fn source_name(&self) -> std::string::String {
        self.src.name()
    }

    /// A one-line progress description for logs.
    pub fn describe(&self) -> std::string::String {
        format!(
            "{}: {} frames, {} bytes consumed, next seq {}",
            self.source_name(), self.frames, self.pos, self.next_seq)
    }
}

/// Materialize every frame of `src` into an owned list (for tooling and
/// tests; production readers stream frame by frame instead).
pub fn read_all_frames(src: Box<dyn Src>) -> Result<Vec<Frame>> {
    let mut reader = FrameReader::open(src);
    let mut out: Vec<Frame> = Vec::new();
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            return std::result::Result::Err(f.unwrap_err());
        }
        let f = f.unwrap();
        if f.is_none() {
            return std::result::Result::Ok(out);
        }
        out.push(f.unwrap());
    }
}

/// A tiny helper that renders a frame like the CLI cat command does.
pub fn describe_frame(f: &Frame) -> std::string::String {
    format!("#{} {} {} {}B",
                         f.seq(), f.kind().name(), f.ts_ms(), f.payload().len())
}
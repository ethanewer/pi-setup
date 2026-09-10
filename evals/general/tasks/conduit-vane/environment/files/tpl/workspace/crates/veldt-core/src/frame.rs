use crate::bytes::{BytesMut, Cursor};
use crate::crc::{crc32_iso, crc32_range};
use crate::error::Error;
use crate::kinds::FrameKind;
use crate::MAX_PAYLOAD_LEN;
use crate::Result;

/// The first byte of every frame. See `docs/FRAME_FORMAT.md`.
pub const MAGIC: u8 = 0xA6;

/// Bytes before the payload in a frame: magic, kind, seq, ts, plen.
pub const HEADER_LEN: usize = 18;

/// Bytes the checksum covers: the header plus the payload.
pub fn checksummed_len(plen: usize) -> usize {
    HEADER_LEN + plen
}

/// A decoded frame. Payloads are owned so that a reader can hand one off
/// without the caller depending on the source buffer's lifetime.
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    kind: FrameKind,
    seq: u32,
    ts_ms: u64,
    payload: Vec<u8>,
}

impl Frame {
    /// Construct a frame with kind, sequence, timestamp and payload.
    pub fn new(kind: FrameKind, seq: u32, ts_ms: u64, payload: Vec<u8>) -> Frame {
        Frame { kind: kind, seq: seq, ts_ms: ts_ms, payload: payload }
    }

    /// The frame kind.
    pub fn kind(&self) -> FrameKind {
        self.kind.clone()
    }

    /// The frame sequence number.
    pub fn seq(&self) -> u32 {
        self.seq
    }

    /// The capture-local timestamp in milliseconds.
    pub fn ts_ms(&self) -> u64 {
        self.ts_ms
    }

    /// The payload bytes.
    pub fn payload(&self) -> &[u8] {
        self.payload.as_slice()
    }

    /// Mutable access to the payload (for assembling frames).
    pub fn payload_mut(&mut self) -> &mut Vec<u8> {
        &mut self.payload
    }

    /// The number of bytes this frame occupies on the wire.
    pub fn length_bytes(&self) -> usize {
        checksummed_len(self.payload.len()) + 4
    }

    /// Append this frame's encoded form (including its checksum) to `buf`.
    pub fn encode_into(&self, buf: &mut BytesMut) {
        buf.push_u8(MAGIC);
        buf.push_u8(self.kind.tag());
        buf.push_u32_le(self.seq);
        buf.push_u64_le(self.ts_ms);
        buf.push_u32_le(self.payload.len() as u32);
        buf.push_bytes(self.payload());
        let crc = crc32_iso(buf.as_slice());
        buf.push_u32_le(crc);
    }

    /// Encode the frame to a fresh byte vector.
    pub fn encode(&self) -> Vec<u8> {
        let mut buf = BytesMut::with_capacity(self.length_bytes());
        self.encode_into(&mut buf);
        buf.to_vec()
    }

    /// Decode one frame from the cursor.
    ///
    /// The cursor must be positioned at the frame's magic byte. On any
    /// protocol violation a typed error is returned; the cursor's position
    /// after an error is unspecified.
    pub fn decode(c: &mut Cursor) -> Result<Frame> {
        let start = c.pos();
        let magic = c.read_u8();
        if magic.is_err() {
            return std::result::Result::Err(magic.unwrap_err());
        }
        if magic.unwrap() != MAGIC {
            return std::result::Result::Err(Error::BadMagic);
        }
        let tag = c.read_u8();
        if tag.is_err() {
            return std::result::Result::Err(tag.unwrap_err());
        }
        let kind = FrameKind::from_tag(tag.unwrap());
        if kind.is_none() {
            return std::result::Result::Err(
                Error::invalid_arg("unknown frame kind tag"));
        }
        let seq = c.read_u32_le();
        if seq.is_err() {
            return std::result::Result::Err(seq.unwrap_err());
        }
        let ts = c.read_u64_le();
        if ts.is_err() {
            return std::result::Result::Err(ts.unwrap_err());
        }
        let plen = c.read_u32_le();
        if plen.is_err() {
            return std::result::Result::Err(plen.unwrap_err());
        }
        let plen = plen.unwrap();
        if plen > MAX_PAYLOAD_LEN {
            return std::result::Result::Err(Error::invalid_arg("payload too large"));
        }
        let payload = c.read_vec(plen as usize);
        if payload.is_err() {
            return std::result::Result::Err(payload.unwrap_err());
        }
        let declared = c.read_u32_le();
        if declared.is_err() {
            return std::result::Result::Err(declared.unwrap_err());
        }
        // Everything between the magic byte and the end of the payload is
        // covered by the checksum; recompute it over the window we read.
        let window_len = checksummed_len(plen as usize);
        let actual = crc32_range(c.base_slice(), start, start + window_len);
        if actual != declared.unwrap() {
            return std::result::Result::Err(Error::BadChecksum);
        }
        std::result::Result::Ok(
            Frame {
                kind: kind.unwrap(),
                seq: seq.unwrap(),
                ts_ms: ts.unwrap(),
                payload: payload.unwrap(),
            },
        )
    }

    /// Decode one frame from a byte slice that starts at its magic byte.
    pub fn decode_slice(data: &[u8]) -> Result<Frame> {
        let mut c = Cursor::over(data);
        Frame::decode(&mut c)
    }
}
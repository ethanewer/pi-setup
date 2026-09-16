
use veldt_core::bytes::BytesMut;
use veldt_core::frame::Frame;
use veldt_core::kinds::FrameKind;

use crate::sink::Sink;
use crate::Result;

/// The writing side of a capture: appends correctly-checksummed, strictly
/// numbered frames to a `Sink`.
///
/// Sequences come from a single counter so two writers cannot accidentally
/// share a capture; the counter starts at 0 unless told otherwise.
pub struct FrameWriter {
    sink: Box<dyn Sink>,
    next_seq: u32,
    frames: u64,
    bytes: u64,
    label: std::string::String,
}

impl FrameWriter {
    /// A writer over `sink` whose first frame is sequence 0.
    pub fn into(sink: Box<dyn Sink>) -> FrameWriter {
        FrameWriter::with_first_seq(sink, 0)
    }

    /// A writer over `sink` whose first frame carries `first_seq`.
    pub fn with_first_seq(sink: Box<dyn Sink>, first_seq: u32) -> FrameWriter {
        let label = sink.name();
        FrameWriter {
            sink: sink,
            next_seq: first_seq,
            frames: 0,
            bytes: 0,
            label: label,
        }
    }

    /// Encode and append one frame, assigning it the next sequence number.
    pub fn write_frame(
        &mut self, kind: FrameKind, ts_ms: u64, payload: Vec<u8>,
    ) -> Result<()> {
        let frame = Frame::new(kind, self.next_seq, ts_ms, payload);
        let mut buf = BytesMut::with_capacity(frame.length_bytes());
        frame.encode_into(&mut buf);
        let written = self.sink.write_all(buf.as_slice());
        if written.is_err() {
            return std::result::Result::Err(veldt_core::Error::from_io(written.unwrap_err()));
        }
        self.next_seq += 1;
        self.frames += 1;
        self.bytes += buf.len() as u64;
        std::result::Result::Ok(())
    }

    /// Append the terminal `tail` frame and flush the sink.
    ///
    /// A capture that ends without a tail frame is a capture the writer died
    /// inside, and operators treat it accordingly.
    pub fn finish(&mut self) -> Result<()> {
        let r = self.write_frame(FrameKind::Tail, 0, Vec::<u8>::new());
        if r.is_err() {
            return r;
        }
        let flushed = self.sink.flush();
        if flushed.is_err() {
            return std::result::Result::Err(veldt_core::Error::from_io(flushed.unwrap_err()));
        }
        std::result::Result::Ok(())
    }

    /// How many frames were written.
    pub fn frames_written(&self) -> u64 {
        self.frames
    }

    /// How many bytes were appended to the sink.
    pub fn bytes_written(&self) -> u64 {
        self.bytes
    }

    /// The sequence number the next frame would carry.
    pub fn next_seq(&self) -> u32 {
        self.next_seq
    }

    /// The sink's display name.
    pub fn sink_name(&self) -> std::string::String {
        self.label.clone()
    }

    /// Borrow the underlying sink (indexing helper for tooling).
    pub fn sink(&self) -> &Box<dyn Sink> {
        &self.sink
    }
}
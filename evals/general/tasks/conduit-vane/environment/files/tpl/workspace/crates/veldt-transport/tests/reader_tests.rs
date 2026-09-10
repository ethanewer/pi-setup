
use veldt_core::frame::Frame;
use veldt_core::kinds::FrameKind;

use veldt_transport::reader::{FrameReader, read_all_frames};
use veldt_transport::session::Session;
use veldt_transport::sink::{FileSink, MemSink, NullSink, Sink};
use veldt_transport::source::{ChainedSource, FileSource, MemSource, Src};
use veldt_transport::writer::FrameWriter;

fn sample_frames() -> Vec<Frame> {
    let mut out: Vec<Frame> = Vec::new();
    out.push(Frame::new(FrameKind::Manifest, 0, 1_000,
                        "capture demo".as_bytes().to_vec()));
    out.push(Frame::new(FrameKind::Sample, 1, 1_010, [0; 0].to_vec()));
    out.push(Frame::new(FrameKind::Status, 2, 1_020,
                        "station ok".as_bytes().to_vec()));
    out.push(Frame::new(FrameKind::Alarm, 3, 1_030,
                        "high temp".as_bytes().to_vec()));
    out.push(Frame::new(FrameKind::Heartbeat, 4, 1_040, [].to_vec()));
    out.push(Frame::new(FrameKind::Tail, 5, 1_050, [].to_vec()));
    out
}

/// Serialise `frames` through a real FrameWriter into a scratch file and
/// return its path.
fn write_capture(name: &str, frames: &Vec<Frame>) -> std::string::String {
    let path = format!("/tmp/{}", name);
    let sink = FileSink::create(&path).unwrap();
    let mut writer = FrameWriter::into(Box::new(sink));
    for f in frames {
        assert!(writer.write_frame(f.kind(), f.ts_ms(), f.payload().to_vec()).is_ok());
    }
    assert!(writer.frames_written() == frames.len() as u64);
    assert!(writer.finish().is_ok());
    path
}

fn read_all(path: &str) -> Vec<Frame> {
    let src = FileSource::open(path).unwrap();
    read_all_frames(Box::new(src)).unwrap()
}

fn unlink(path: &str) {
    let _ = std::fs::remove_file(path);
}

#[test]
fn writer_to_file_to_reader_roundtrip() {
    let frames = sample_frames();
    let path = write_capture("vt-demo.bin", &frames);
    let back = read_all(&path);
    unlink(&path);
    // finish() appends a numbered tail frame; a well-formed capture ends
    // with one (FRAME_FORMAT.md), so the read-back holds one more frame
    // than was written by hand.
    assert!(back.len() == frames.len() + 1);
    assert!(back[frames.len()].kind() == FrameKind::Tail);
    for i in 0..frames.len() {
        let a = frames[i].clone();
        let b = back[i].clone();
        assert!(a.kind() == b.kind());
        assert!(a.seq() == b.seq());
        assert!(a.ts_ms() == b.ts_ms());
        assert!(a.payload() == b.payload());
    }
}

#[test]
fn reader_reports_progress_and_clean_eof() {
    let path = write_capture("vt-progress.bin", &sample_frames());
    let src = FileSource::open(&path);
    let mut reader = FrameReader::open(Box::new(src.unwrap()));
    let mut count: u64 = 0;
    loop {
        let f = reader.read_frame().unwrap();
        if f.is_none() {
            break;
        }
        assert!(count == f.unwrap().seq() as u64);
        count += 1;
    }
    assert!(count == 7);
    assert!(reader.frames_read() == 7);
    assert!(reader.last_seq() == 6);
    assert!(reader.bytes_consumed() > 0);
    reader.reset();
    assert!(reader.read_frame().unwrap().is_some());
    assert!(reader.gaps() == 0);
    assert!(reader.source_len() > 0);
    assert!(reader.is_strict());
    unlink(&path);
}

#[test]
fn truncated_stream_is_an_error_not_a_panic() {
    let path = write_capture("vt-trunc.bin", &sample_frames());
    let whole = std::fs::read(&path).unwrap();
    let cut = whole[0..whole.len() - 3].to_vec();
    let out_path = "/tmp/vt-trunc2.bin";
    let mut sink = FileSink::create(out_path).unwrap();
    sink.write_all(cut.as_slice()).unwrap();
    sink.flush().unwrap();
    let mut reader = FrameReader::open(
        Box::new(FileSource::open(out_path).unwrap()));
    let mut ok_frames = 0;
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            // A truncated tail is the expected failure mode.
            assert!(f.unwrap_err().kind() == "truncated");
            assert!(ok_frames >= 5);
            unlink(&path);
            let _ = std::fs::remove_file(out_path);
            return;
        }
        let opt = f.unwrap();
        if opt.is_some() {
            ok_frames += 1;
            continue;
        }
        break;
    }
    assert!(false);
}

#[test]
fn corrupted_stream_is_detected() {
    let path = write_capture("vt-corrupt.bin", &sample_frames());
    let whole = std::fs::read(&path).unwrap();
    let mut bytes = whole;
    bytes.as_mut_slice()[25] ^= 0x40;
    let corrupted = "/tmp/vt-corrupt2.bin";
    let mut sink = FileSink::create(corrupted).unwrap();
    sink.write_all(bytes.as_slice()).unwrap();
    sink.flush().unwrap();
    let mut reader = FrameReader::open(
        Box::new(FileSource::open(corrupted).unwrap()));
    loop {
        let f = reader.read_frame();
        if f.is_err() {
            assert!(f.unwrap_err().kind() == "bad-checksum");
            unlink(&path);
            let _ = std::fs::remove_file(corrupted);
            return;
        }
        if f.unwrap().is_none() {
            assert!(false);
        }
    }
}

#[test]
fn nonstrict_reader_tolerates_a_gap() {
    let frames: Vec<Frame> = [
        Frame::new(FrameKind::Status, 0, 10, "first".as_bytes().to_vec()),
        Frame::new(FrameKind::Status, 2, 12, "third".as_bytes().to_vec()),
    ].to_vec();
    // Serialise with explicit sequence numbers via Frame::encode.
    let mut buf: Vec<u8> = Vec::new();
    for f in frames {
        for b in f.encode() {
            buf.push(b);
        }
    }
    let src = MemSource::from_bytes(buf.clone());
    let mut strict = FrameReader::open(Box::new(src));
    assert!(strict.read_frame().is_ok());
    assert!(strict.read_frame().is_err());

    let src2 = MemSource::from_bytes(buf.clone());
    let mut lenient = FrameReader::open_nonstrict(Box::new(src2));
    assert!(lenient.read_frame().is_ok());
    assert!(lenient.read_frame().is_ok());
    assert!(lenient.gaps() == 1);
}

#[test]
fn chained_source_reads_across_segments() {
    let mut parts: Vec<Box<dyn Src>> = Vec::new();
    parts.push(Box::new(MemSource::from_slice([0x01, 0x02, 0x03].as_slice())));
    parts.push(Box::new(MemSource::from_slice([0x04, 0x05].as_slice())));
    parts.push(Box::new(MemSource::from_slice([0x06, 0x07, 0x08, 0x09].as_slice())));
    let chain = ChainedSource::of(parts);
    assert!(chain.len() == 9);
    let mut nine: [u8; 9] = [0; 9];
    let got = chain.read_at(0, nine.as_mut_slice());
    assert!(got.unwrap() == 9);
    assert!(nine[0] == 0x01 && nine[8] == 0x09);
    let mut r2: [u8; 4] = [0; 4];
    let got2 = chain.read_at(4, r2.as_mut_slice());
    assert!(got2.unwrap() == 4);
    assert!(r2[0] == 0x05 && r2[3] == 0x08);
    assert!(chain.name().len() > 0);
}

#[test]
fn session_tracks_acknowledgements() {
    let mut sess = Session::new("well-2");
    assert!(sess.register_frame(0));
    assert!(sess.register_frame(1));
    assert!(!sess.register_frame(1));
    assert!(sess.register_frame(3));
    assert!(sess.contiguous() == 2);
    assert!(sess.seen(3));
    assert!(sess.endpoint() == "well-2");
    assert!(sess.summary().len() > 8);
}

#[test]
fn null_sink_counts_bytes() {
    let mut sink = NullSink::new("dry-run");
    assert!(sink.write_all([1, 2, 3].as_slice()).is_ok());
    assert!(sink.write_all([].as_slice()).is_ok());
    assert!(sink.fed() == 3);
    assert!(sink.flush().is_ok());
}

#[test]
fn memory_source_and_sink_agree() {
    let mut sink = MemSink::new();
    assert!(sink.write_all([9, 8, 7].as_slice()).is_ok());
    let src = MemSource::from_slice(sink.bytes());
    let mut buf: [u8; 3] = [0; 3];
    assert!(src.read_at(0, buf.as_mut_slice()).unwrap() == 3);
    assert!(buf[2] == 7);
    let mut one: [u8; 1] = [0; 1];
    assert!(src.read_at(2, one.as_mut_slice()).unwrap() == 1);
    assert!(src.read_at(99, buf.as_mut_slice()).unwrap() == 0);
}
// The station (fob) consumer: the downstream SDK that the resume capability
// was built for.
//
// It exercises the capability exactly the way a fob would after a power
// loss:
//
//   1. read the whole capture from the start;
//   2. read half of it, take a checkpoint, and persist it as bytes;
//   3. "boot" again: load the checkpoint from bytes and resume the capture;
//   4. assert the resumed tail is byte-for-byte the tail of the full read;
//   5. assert a checkpoint taken at the very end resumes to clean EOF;
//   6. assert `Checkpoint::empty()` resumes equivalently to `from_start`.
//
// Exit 0 only when every step holds. No fixture expectation is embedded;
// everything the consumer checks derives from the capture it is handed and
// the contract in docs/INTEGRATION.md.

use std::io;
use std::io::Write;

use veldt_core::crc::crc32_iso;
use veldt_core::frame::Frame;
use veldt_transport::resume::{Checkpoint, ResumableReader};
use veldt_transport::source::{FileSource, Src};

struct Rec {
    seq: u32,
    kind: u8,
    plen: usize,
    crc: u32,
}

fn rec_of(f: &Frame) -> Rec {
    Rec { seq: f.seq(), kind: f.kind().tag(), plen: f.payload().len(),
          crc: crc32_iso(f.payload()) }
}

fn open_src(path: &str) -> Box<dyn Src> {
    Box::new(FileSource::open(path).unwrap())
}

fn collect_all(r: &mut ResumableReader) -> Vec<Rec> {
    let mut out: Vec<Rec> = Vec::new();
    loop {
        let f = r.read_frame();
        if f.is_err() {
            fail(format!("read failed on {}", r.bytes_consumed()));
        }
        let f = f.unwrap();
        if f.is_none() {
            return out;
        }
        out.push(rec_of(&f.unwrap()));
    }
}

fn fail(message: std::string::String) {
    let mut buf = message;
    buf.push_str("\n");
    io::stderr().write_all(buf.as_bytes()).unwrap();
    std::process::exit(1);
}

fn check(cond: bool, message: std::string::String) {
    if !cond {
        fail(message);
    }
}

fn main() -> io::Result<()> {
    let mut argv: Vec<std::string::String> = Vec::new();
    for arg in std::env::args() {
        argv.push(arg.clone());
    }
    if argv.len() < 2 {
        fail(format!("usage: station <capture>"));
    }
    let path = argv[1].clone();

    // 1. full read
    let mut full_r = ResumableReader::from_start(open_src(&path));
    if full_r.is_err() {
        fail(format!("from_start rejected the capture"));
    }
    let full = collect_all(&mut full_r.unwrap());
    if full.is_empty() {
        fail(format!("capture contained no frames"));
    }

    // 2. read half, take a checkpoint, persist it
    let k = full.len() / 2;
    let mut mid_r = ResumableReader::from_start(open_src(&path)).unwrap();
    let mut skipped: usize = 0;
    while skipped < k {
        let f = mid_r.read_frame().unwrap();
        if f.is_none() {
            fail(format!("capture ended before the midpoint"));
        }
        skipped += 1;
    }
    check(mid_r.frames_read() == k as u64, format!("frames_read mismatch at midpoint"));
    let cp = mid_r.checkpoint();
    check(cp.position() == mid_r.bytes_consumed(),
          format!("checkpoint position must equal bytes consumed"));
    let blob = cp.to_bytes();
    if blob.is_empty() {
        fail(format!("checkpoint blob is empty"));
    }

    // 3. blackout: the blob is all that survives; boot from bytes
    let cp2 = Checkpoint::from_bytes(blob.as_slice());
    if cp2.is_err() {
        fail(format!("persisted checkpoint would not load"));
    }

    // 4. resume on a fresh source handle
    let mut res_r = ResumableReader::resume(open_src(&path), cp2.unwrap());
    if res_r.is_err() {
        fail(format!("resume rejected a checkpoint it produced itself"));
    }
    let mut resumed = res_r.unwrap();
    let rest = collect_all(&mut resumed);
    check(rest.len() == full.len() - k,
          format!("resumed tail length does not match the full read"));
    for i in 0..rest.len() {
        let got = &rest[i];
        let want = &full[k + i];
        if got.seq != want.seq || got.kind != want.kind
           || got.plen != want.plen || got.crc != want.crc {
            fail(format!(
                "resumed frame {} differs from the full read at index {}",
                got.seq, k + i));
        }
    }

    // 5. a checkpoint at the very end resumes to clean EOF
    let cp_end = resumed.checkpoint();
    let end_pos = cp_end.position();
    let mut tail_r = ResumableReader::resume(open_src(&path), cp_end).unwrap();
    let after = tail_r.read_frame().unwrap();
    check(after.is_none(), format!("resuming from the end must yield clean EOF"));
    check(tail_r.bytes_consumed() == end_pos,
          format!("EOF resume reported a surprising position"));

    // 6. empty checkpoint == from_start
    let mut empty_r =
        ResumableReader::resume(open_src(&path), Checkpoint::empty()).unwrap();
    let first = empty_r.read_frame();
    if first.is_err() {
        fail(format!("empty-checkpoint resume failed"));
    }
    let first_opt = first.unwrap();
    check(first_opt.is_some(), format!("empty checkpoint resumed to nothing"));
    let first = first_opt.unwrap();
    check(first.seq() == full[0].seq
              && first.kind().tag() == full[0].kind
              && first.payload().len() == full[0].plen,
          format!("empty checkpoint did not reproduce the first frame"));

    print_line(format!(
        "STATION OK frames={} mid={} resumed={}", full.len(), k, rest.len()));
    std::result::Result::Ok(())
}

fn print_line(s: std::string::String) {
    let mut buf = s;
    buf.push_str("\n");
    io::stdout().write_all(buf.as_bytes()).unwrap();
}
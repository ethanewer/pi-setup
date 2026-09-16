// The resilience consumer: probes the resume capability's *failure* paths.
//
// A checkpoint system that never failed would be a dangerous one: the whole
// point of the blob is that a corrupt blob or a changed capture is refused
// loudly instead of silently resuming at the wrong place. This consumer
// checks, against a real capture and a real checkpoint:
//
//   * corrupted checkpoint blobs (every byte position, one at a time) are
//     rejected by `Checkpoint::from_bytes` with a typed error, never a panic;
//   * empty / short / oversized / random inputs are rejected;
//   * a valid checkpoint resumed against a source whose consumed prefix was
//     modified is refused;
//   * a source shorter than the checkpointed prefix is refused;
//   * a source truncated exactly at the checkpoint resumes to clean EOF and
//     a source truncated inside the next frame fails with a truncation error;
//   * `Checkpoint::empty()` resumes like `from_start`.
//
// Exit 0 only when every probe behaves as the contract promises.

use std::io;
use std::io::Write;

use veldt_transport::resume::{Checkpoint, ResumableReader};
use veldt_transport::source::{MemSource, Src};

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

fn mem(bytes: &[u8]) -> Box<dyn Src> {
    Box::new(MemSource::from_slice(bytes))
}

fn expect_err_bytes(data: &[u8], label: std::string::String) {
    let r = Checkpoint::from_bytes(data);
    check(r.is_err(), format!("{} was accepted", label));
}

fn print_line(s: std::string::String) {
    let mut buf = s;
    buf.push_str("\n");
    io::stdout().write_all(buf.as_bytes()).unwrap();
}

fn main() -> io::Result<()> {
    let mut argv: Vec<std::string::String> = Vec::new();
    for arg in std::env::args() {
        argv.push(arg.clone());
    }
    if argv.len() < 2 {
        fail(format!("usage: resilience <capture>"));
    }
    let path = argv[1].clone();

    // Read the whole capture into memory once; the probes below operate on
    // modified copies of these bytes.
    let read = std::fs::read(&path);
    if read.is_err() {
        fail(format!("cannot read '{}'", path));
    }
    let whole = read.unwrap().to_vec();
    if whole.is_empty() {
        fail(format!("capture file is empty"));
    }

    // Baseline: the fixture parses from start to finish.
    let mut r0 = ResumableReader::from_start(mem(whole.as_slice())).unwrap();
    let mut count: u64 = 0;
    loop {
        let f = r0.read_frame();
        if f.is_err() {
            fail(format!("baseline read failed at {}", r0.bytes_consumed()));
        }
        if f.unwrap().is_none() {
            break;
        }
        count += 1;
    }
    check(count > 0, format!("baseline produced zero frames"));

    // Take a real checkpoint at the midpoint (or the start for a capture
    // with a single frame).
    let half = count / 2;
    let mut mid_r = ResumableReader::from_start(mem(whole.as_slice())).unwrap();
    let mut seen: u64 = 0;
    while seen < half {
        let f = mid_r.read_frame();
        if f.is_err() || f.unwrap().is_none() {
            fail(format!("capture ended before the midpoint"));
        }
        seen += 1;
    }
    let cp = mid_r.checkpoint();
    let pos = cp.position();
    let blob = cp.to_bytes();

    // ---- probe 1: from_bytes rejects every single-byte corruption ----
    for flip in 0..blob.len() {
        let mut corrupt = blob.clone();
        corrupt[flip] ^= 0x01;
        let r = Checkpoint::from_bytes(corrupt.as_slice());
        check(r.is_err(), format!(
            "single-byte corruption at offset {} was accepted", flip));
    }

    // ---- probe 2: malformed inputs are rejected, never panics ----
    let empty: [u8; 0] = [];
    expect_err_bytes(empty.as_slice(), format!("empty input"));
    let short: [u8; 3] = [0x56, 0x44, 0x43];
    expect_err_bytes(short.as_slice(), format!("short input"));
    let zeros: [u8; 25] = [0; 25];
    expect_err_bytes(zeros.as_slice(), format!("zero-filled input"));
    let mut random: [u8; 25] = [0; 25];
    for i in 0..25 {
        random[i] = ((i * 37 + 11) % 256) as u8;
    }
    expect_err_bytes(random.as_slice(), format!("random input"));
    let mut oversized: Vec<u8> = Vec::new();
    for _ in 0..5000 {
        oversized.push(0x41);
    }
    expect_err_bytes(oversized.as_slice(), format!("oversized input"));
    // sanity: the pristine blob still parses
    check(Checkpoint::from_bytes(blob.as_slice()).is_ok(),
          format!("the pristine checkpoint stopped parsing"));

    // ---- probe 3: changed consumed prefix is refused ----
    if pos > 0 {
        let mut changed_prefix = whole.clone();
        let flip_at = (pos - 1) as usize;
        changed_prefix.as_mut_slice()[flip_at] ^= 0xFF;
        let bad_r = ResumableReader::resume(mem(changed_prefix.as_slice()), cp.clone());
        check(bad_r.is_err(), format!("a modified consumed prefix was accepted"));
    }

    // ---- probe 4: source shorter than the checkpointed prefix is refused ----
    if pos > 0 {
        let short_len = (pos - 1) as usize;
        let short_src = whole[0..short_len].to_vec();
        let short_r = ResumableReader::resume(mem(short_src.as_slice()), cp.clone());
        check(short_r.is_err(), format!("a too-short source was accepted"));
    }

    // ---- probe 5: truncated exactly at the checkpoint resumes to EOF ----
    let cut_at = pos as usize;
    if cut_at <= whole.len() {
        let exact_src = whole[0..cut_at].to_vec();
        let mut exact_r =
            ResumableReader::resume(mem(exact_src.as_slice()), cp.clone());
        if exact_r.is_err() {
            fail(format!("a capture trimmed at the checkpoint was refused"));
        }
        let after = exact_r.unwrap().read_frame().unwrap();
        check(after.is_none(), format!("resume at EOF did not yield clean EOF"));
    }

    // ---- probe 6: truncated mid-frame yields a truncation error ----
    if pos + 6 < whole.len() as u64 {
        let mid_len = (pos as usize) + 6;
        let mid_src = whole[0..mid_len].to_vec();
        let mut mid_r2 = ResumableReader::resume(mem(mid_src.as_slice()), cp).unwrap();
        let f = mid_r2.read_frame();
        check(f.is_err() && f.unwrap_err().kind() == "truncated",
              format!("mid-frame truncation was not reported as truncated"));
    }

    // ---- probe 7: empty checkpoint is equivalent to from_start ----
    let mut emp_r =
        ResumableReader::resume(mem(whole.as_slice()), Checkpoint::empty()).unwrap();
    let first = emp_r.read_frame().unwrap();
    check(first.is_some(), format!("empty checkpoint resumed to nothing"));
    check(first.unwrap().seq() == 0, format!("empty checkpoint did not start at seq 0"));

    print_line(format!("RESILIENCE OK frames={} pos={}",
                                    count, pos));
    std::result::Result::Ok(())
}
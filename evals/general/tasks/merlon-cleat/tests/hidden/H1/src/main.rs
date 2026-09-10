//! rivetscan — hidden consumer H1.
//!
//! Builds a deterministic stream of Pennant frames (boundary tags and
//! length values, pseudo-random payloads), then exercises the public API:
//!
//!   - decode_first walks the whole stream, frame by frame;
//!   - every frame is re-encoded with encode_frame (into a buffer sized
//!     with frame_capacity) and must be byte-identical to the original;
//!   - varint_len agrees with the actual varint byte counts in the stream;
//!   - decode_frame treats the stream as one frame (fails: trailing bytes)
//!     and accepts a single frame;
//!   - truncated and corrupted variants fail with the documented errors.
//!
//! This crate is compiled unchanged against the pennant crate under test.
//! It expects the v0.1 public API; if the API changed, it must not compile,
//! and if behavior changed, its assertions must fail.

use pennant::{MAGIC, decode_first, decode_frame, encode_frame, frame_capacity,
              varint_len, FrameError};

const N_FRAMES: u32 = 347;

const TAG_POOL: &[u64] = &[0, 1, 127, 128, 300, 16383, 16384, 65535,
                          0xFFFFFFFF, 99991, 18446744073709551615];
const LEN_POOL: &[usize] = &[0, 1, 2, 7, 63, 127, 200, 255, 511, 1024];

struct Rng {
    x: u64,
}

impl Rng {
    fn new(seed: u64) -> Rng {
        Rng { x: seed + 0x9E3779B97F4A7C15 }
    }
    fn next(self: &mut Rng) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 41;
        self.x = x;
        x
    }
}

fn frame_at(i: u32, rng: &mut Rng) -> (u64, Vec<u8>) {
    let tag = TAG_POOL[(i * 7 % 11) as usize];
    let len_id = (i * 3 + i / 5) % 10;
    let len = LEN_POOL[len_id as usize];
    let mut payload = Vec::with_capacity(len);
    for _ in 0..len {
        payload.push((rng.next() & 0xFF) as u8);
    }
    (tag, payload)
}

fn bytes_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    for i in 0..a.len() {
        if a[i] != b[i] {
            return false;
        }
    }
    true
}

fn check(cond: bool, what: &str) {
    if !cond {
        panic!("H1-FAIL {what}");
    }
}

fn fe_text(e: FrameError) -> &'static str {
    match e {
        FrameError::BadMagic => "bad-magic",
        FrameError::Truncated => "truncated",
    }
}

fn main() {
    // 1. Build the stream exactly as the API specifies.
    let mut rng = Rng::new(0x51);
    let mut stream: Vec<u8> = Vec::new();
    let mut sink: Vec<u8> = Vec::with_capacity(2048);
    let mut total: usize = 0;
    let mut frames: Vec<(u64, usize)> = Vec::with_capacity(N_FRAMES as usize);
    for i in 0..N_FRAMES {
        let (tag, payload) = frame_at(i, &mut rng);
        sink.clear();
        let n = encode_frame(tag, &payload, &mut sink);
        check(n == frame_capacity(tag, payload.len()), "frame_capacity exact");
        check(n == 1 + varint_len(tag) + varint_len(payload.len() as u64) + payload.len(),
              "capacity matches spec arithmetic");
        stream.extend(sink.iter().copied());
        frames.push((tag, n));
        total += n;
    }
    check(stream.len() == total, "stream length equals frame total");

    // 2. Scan the stream with decode_first; re-encode each frame and check
    //    byte equality with the source slice.
    let mut offset: usize = 0;
    let mut seen: usize = 0;
    while offset < stream.len() {
        match decode_first(&stream[offset..]) {
            Err(e) => {
                let m = fe_text(e);
                panic!("H1-FAIL scan error mid-stream: {m}");
            },
            Ok((f, used)) => {
                check(used >= 3, "frame uses at least 3 bytes");
                check(f.tag == frames[seen].0, "tag order matches");
                check(used == frames[seen].1, "frame size matches");
                // Independent re-encode must reproduce the exact bytes.
                sink.clear();
                let n = encode_frame(f.tag, f.payload, &mut sink);
                check(bytes_eq(&sink, &stream[offset..offset + used]), "re-encode");
                check(n == used, "re-encode size");
                // decode_frame accepts exactly this frame.
                match decode_frame(&stream[offset..offset + used]) {
                    Err(e) => {
                        let m = fe_text(e);
                        panic!("H1-FAIL strict decode of single frame: {m}");
                    },
                    Ok(g) => check(g.tag == f.tag && bytes_eq(g.payload, f.payload),
                                    "strict decode content"),
                }
                offset += used;
                seen += 1;
            },
        }
    }
    check(seen == N_FRAMES as usize, "scanned the full stream");

    // 3. Error behavior on corrupt inputs.
    let mut corrupt = stream.clone();
    corrupt[0] = 0x11;
    match decode_first(&corrupt) {
        Err(FrameError::BadMagic) => {}
        _ => panic!("H1-FAIL corrupted magic must be BadMagic"),
    }
    // Cut one byte off the end of the *first* frame: decode_first only
    // reads from the front, so the corruption must be at the front.
    let first_frame = frames[0].1;
    check(first_frame >= 3, "first frame is big enough to truncate");
    let short = &stream[..first_frame - 1];
    match decode_first(short) {
        Err(FrameError::Truncated) => {}
        _ => panic!("H1-FAIL truncated stream must be Truncated"),
    }
    match decode_frame(&stream[..stream.len() - 3]) {
        Err(FrameError::Truncated) => {}
        _ => panic!("H1-FAIL cut tail must fail strict decode"),
    }
    match decode_frame(&stream) {
        Err(FrameError::Truncated) => {}
        _ => panic!("H1-FAIL multi-frame stream must fail strict decode"),
    }
    // Empty input is BadMagic.
    match decode_first(&[]) {
        Err(FrameError::BadMagic) => {}
        _ => panic!("H1-FAIL empty input must be BadMagic"),
    }
    // Overlong varint (11 continuation groups) is Truncated.
    let overlong: &[u8] = &[0xA7, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
                            0x80, 0x80, 0x80, 0x80];
    match decode_first(overlong) {
        Err(FrameError::Truncated) => {}
        _ => panic!("H1-FAIL overlong varint must be Truncated"),
    }

    // 4. Boundary tags must round-trip both directions.
    let tiny: Vec<u8> = Vec::new();
    for t in TAG_POOL {
        let t = *t;
        sink.clear();
        let n = encode_frame(t, &tiny, &mut sink);
        match decode_first(&sink) {
            Err(e) => {
                let m = fe_text(e);
                panic!("H1-FAIL boundary tag {t}: {m}");
            },
            Ok((f, used)) => {
                check(f.tag == t, "boundary tag roundtrip");
                check(used == n, "boundary tag size");
            },
        }
    }

    println!("H1-OK frames={} bytes={}", seen, total);
}
//! pennant-bench: measures encode_frame of the crate under test against the
//! reference (baseline) implementation baked into the image.
//!
//! Modes (argv[1]):
//!   load  - build the corpus and walk it, encoding nothing. Establishes the
//!           allocation total for startup + corpus build.
//!   ref   - corpus + encode every frame with the reference v0.1 crate.
//!   agent - corpus + encode every frame with the crate under test.
//!   both  - corpus, then reference and candidate back to back in one
//!           process; prints per-library micros and whether the two emit
//!           identical bytes.
//!
//! Under LD_PRELOAD=/opt/libcountallocs.so with ALLOCLOG=/path set, the shim
//! writes the process-wide malloc-family call count to that file at exit.
//! The verifier subtracts the `load` total from the `ref`/`agent` totals to
//! attribute allocations to the encode loop alone.
//!
//! The corpus is deterministic (fixed seed) and single-threaded.

use std::time::Instant;
use pennant::{decode_first, encode_frame as agent_encode};
use pennant_baseline::{encode_frame as ref_encode};

const FRAMES: u32 = 300_000;
const SINK_CAP: usize = 4 << 20;
const SEED: u64 = 0x6D6572_6C6F_6E;
const SEED2: u64 = 0xC0FFEE_DEAD_BEEF;

struct Rng {
    x: u64,
}

impl Rng {
    fn new(seed: u64) -> Rng {
        Rng { x: seed }
    }
    fn next(self: &mut Rng) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        x
    }
}

fn build_corpus() -> Vec<(u64, Vec<u8>)> {
    let mut rng = Rng::new(SEED);
    let mut corpus: Vec<(u64, Vec<u8>)> = Vec::with_capacity(FRAMES as usize);
    for _ in 0..FRAMES {
        let len = 1 + (rng.next() % 160) as usize;
        let tag = rng.next() % 1_000_003;
        let mut payload = Vec::with_capacity(len);
        for _ in 0..len {
            payload.push((rng.next() & 0xFF) as u8);
        }
        corpus.push((tag, payload));
    }
    corpus
}

fn mix(h: u64, b: u8) -> u64 {
    let mut x = h ^ b as u64;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}

fn digest_of(h: u64, buf: &[u8]) -> u64 {
    let mut d = h;
    for b in buf {
        d = mix(d, *b);
    }
    d
}

fn slice_eq(a: &[u8], b: &[u8]) -> bool {
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

/// Encode every frame in `corpus` with the selected library (0 = baseline
/// reference, 1 = crate under test). Returns (micros, digest, selftest,
/// bytes). The timed region contains only the per-frame encode (clear +
/// write); full round-trip validation and digests run in a second, untimed
/// pass. `SINK_CAP` is large enough that no frame ever grows the sink, so
/// any heap allocations during the timed region are attributable to the
/// library's own implementation.
fn encode_all(lib: u8, corpus: &Vec<(u64, Vec<u8>)>) -> (u128, u64, bool, usize) {
    let mut sink = Vec::with_capacity(SINK_CAP);
    let mut digest: u64 = SEED2;
    let mut selftest = true;
    let mut bytes: usize = 0;

    let t0 = Instant::now();
    for pair in corpus {
        let tag = pair.0;
        let payload = &pair.1;
        sink.clear();
        let n = match lib {
            0 => ref_encode(tag, payload, &mut sink),
            _ => agent_encode(tag, payload, &mut sink),
        };
        bytes += n;
        let last = sink[sink.len() - 1];
        digest = mix(digest, last);
    }
    let micros = (Instant::now() - t0).as_nanos() / 1000;

    // Untimed validation pass: every frame must decode back to its source
    // and round-trip byte for byte.
    let mut probe: Vec<u8> = Vec::with_capacity(SINK_CAP);
    for pair in corpus {
        let tag = pair.0;
        let payload = &pair.1;
        probe.clear();
        let n = match lib {
            0 => ref_encode(tag, payload, &mut probe),
            _ => agent_encode(tag, payload, &mut probe),
        };
        digest = digest_of(digest, &probe);
        match decode_first(&probe) {
            Err(_) => selftest = false,
            Ok((f, used)) => {
                if used != n || f.tag != tag || !slice_eq(f.payload, payload) {
                    selftest = false;
                }
            },
        }
    }
    (micros, digest, selftest, bytes)
}

fn main() {
    let argv: Vec<String> = std::env::args().collect();
    let mode: &[u8] = argv.get(1).map(|s| s.as_bytes()).unwrap_or(&[]);

    if mode == "load".as_bytes() {
        let corpus = build_corpus();
        let mut sink: Vec<u8> = Vec::with_capacity(SINK_CAP);
        let mut digest: u64 = SEED2;
        for pair in &corpus {
            sink.clear();
            digest = mix(digest, (pair.1.len()) as u8);
        }
        println!("PENNBENCH MODE=load FRAMES={} DIGEST={:x}", FRAMES, digest);
    } else if mode == "ref".as_bytes() {
        let corpus = build_corpus();
        let (micros, digest, selftest, bytes) = encode_all(0, &corpus);
        println!("PENNBENCH MODE=ref FRAMES={} MICROS={} DIGEST={:x} BYTES={} SELFTEST={}",
                 FRAMES, micros, digest, bytes, selftest as usize);
    } else if mode == "agent".as_bytes() {
        let corpus = build_corpus();
        let (micros, digest, selftest, bytes) = encode_all(1, &corpus);
        println!("PENNBENCH MODE=agent FRAMES={} MICROS={} DIGEST={:x} BYTES={} SELFTEST={}",
                 FRAMES, micros, digest, bytes, selftest as usize);
    } else if mode == "both".as_bytes() {
        let corpus = build_corpus();
        let (r_micros, r_digest, r_ok, r_bytes) = encode_all(0, &corpus);
        let (a_micros, a_digest, a_ok, a_bytes) = encode_all(1, &corpus);
        println!("PENNBENCH MODE=both FRAMES={}", FRAMES);
        println!("PENNBENCH REF_MICROS={} AGENT_MICROS={}", r_micros, a_micros);
        println!("PENNBENCH REF_DIGEST={:x} AGENT_DIGEST={:x}", r_digest, a_digest);
        println!("PENNBENCH SAME={} REF_SELFTEST={} AGENT_SELFTEST={} REF_BYTES={} AGENT_BYTES={}",
                 (r_digest == a_digest && r_bytes == a_bytes) as usize,
                 r_ok as usize, a_ok as usize, r_bytes, a_bytes);
    } else {
        println!("usage: pennant-bench (load|ref|agent|both)");
    }
}
//! pennagg — hidden consumer H2.
//!
//! A different consumer shape than H1: generates a synthetic *log* of
//! interleaved Pennant frames (wide tag space, variable payload sizes) with
//! two deliberate corruptions, then:
//!
//!   - walks the log with decode_first, aggregating per-tag payload byte
//!     totals and a rolling mix of every payload byte;
//!   - records the error kinds and offsets of the corrupt regions;
//!   - re-encodes a resampled subset (including encode_text frames) and
//!     verifies the re-encoded stream decodes back to identical content;
//!   - cross-checks frame_capacity against varint_len arithmetic for a
//!     spread of (tag, len) pairs.
//!
//! Compiled unchanged against the pennant crate under test; must stay
//! source-compatible with the documented v0.1 public API.

use pennant::{decode_first, encode_frame, encode_text, frame_capacity, varint_len,
              FrameError};

const N_OK: u32 = 911;
const N_TAIL: u32 = 10;
const WIDE: u64 = 1_000_003;
const SEED: u64 = 0xC0FFEE;

struct Rng {
    x: u64,
}

impl Rng {
    fn next(self: &mut Rng) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 41;
        self.x = x;
        x
    }
}

fn rng_new(seed: u64) -> Rng {
    Rng { x: seed + 0x9E3779B97F4A7C15 }
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
        panic!("H2-FAIL {what}");
    }
}

fn fe_text(e: FrameError) -> &'static str {
    match e {
        FrameError::BadMagic => "bad-magic",
        FrameError::Truncated => "truncated",
    }
}

const LENS_SPREAD: &[usize] = &[0, 1, 127, 200, 4096];

struct Tail {
    ok_frames: usize,
    errors: usize,
    err_kinds: Vec<&'static str>,
    bytes: usize,
    tag_buckets: Vec<u64>,
    mix: u64,
}

fn main() {
    // ---- 1. Build the log. ----
    let mut rng = rng_new(SEED);
    let mut log: Vec<u8> = Vec::new();
    let mut sink: Vec<u8> = Vec::with_capacity(4096);
    let mut build_ok = 0u32;
    for _ in 0..N_OK {
        let tag = rng.next() % WIDE;
        let len = 1 + (rng.next() % 2048) as usize;
        let mut payload = Vec::with_capacity(len);
        for _ in 0..len {
            payload.push((rng.next() & 0xFF) as u8);
        }
        sink.clear();
        encode_frame(tag, &payload, &mut sink);
        log.extend(sink.iter().copied());
        build_ok += 1;
    }
    // Tail frames come before the corruptions so the walk can reach them.
    for _ in 0..N_TAIL {
        let tag = rng.next() % WIDE;
        let mut payload = Vec::with_capacity(3);
        payload.push((rng.next() & 0xFF) as u8);
        payload.push(0x00);
        payload.push(0x01);
        sink.clear();
        encode_frame(tag, &payload, &mut sink);
        log.extend(sink.iter().copied());
    }
    // Corruption 1: four garbage bytes (wrong magic).
    log.extend((&[0x11u8, 0x22, 0x33, 0x44]).iter().copied());
    // Corruption 2: a truncated frame (magic, tag=5, len=3000, 7 bytes only).
    let mut trunc: Vec<u8> = Vec::with_capacity(16);
    trunc.push(0xA7);
    trunc.push(0x05);
    trunc.push(0xB8);
    trunc.push(0x17);
    for _ in 0..7 {
        trunc.push(0xEE);
    }
    log.extend(trunc.iter().copied());

    // ---- 2. Walk the log. ----
    let mut agg: Tail = Tail { ok_frames: 0, errors: 0, err_kinds: Vec::new(),
                               bytes: 0, tag_buckets: Vec::with_capacity(64), mix: SEED };
    let mut offset: usize = 0;
    while offset < log.len() {
        match decode_first(&log[offset..]) {
            Err(e) => {
                agg.errors += 1;
                match e {
                    FrameError::BadMagic => agg.err_kinds.push("BadMagic"),
                    FrameError::Truncated => agg.err_kinds.push("Truncated"),
                }
                // skip the bad stretch; scanning continues from here
                offset += if e == FrameError::BadMagic { 4 } else { 0 };
                if e == FrameError::Truncated {
                    break;
                }
            },
            Ok((f, used)) => {
                agg.ok_frames += 1;
                agg.bytes += f.payload.len();
                let bucket = f.tag % 64;
                while agg.tag_buckets.len() <= bucket as usize {
                    agg.tag_buckets.push(0);
                }
                agg.tag_buckets[bucket as usize] += f.payload.len() as u64;
                for b in f.payload {
                    agg.mix ^= agg.mix << 7;
                    agg.mix ^= *b as u64;
                    agg.mix ^= agg.mix >> 9;
                }
                offset += used;
            },
        }
    }

    // ---- 3. Expectations. ----
    check(agg.ok_frames == (N_OK + N_TAIL) as usize, "frame count");
    check(agg.errors == 2, "error count");
    check(agg.err_kinds.len() == 2, "two recorded errors");
    check(agg.err_kinds[0] == "BadMagic", "first error kind");
    check(agg.err_kinds[1] == "Truncated", "second error kind");
    check(agg.tag_buckets.len() <= 64, "bucket bound");

    // ---- 4. Re-encode a resampled subset and check a full roundtrip. ----
    let mut out: Vec<u8> = Vec::new();
    let mut rng2 = rng_new(SEED + 7);
    for i in 0u32..(N_OK / 7) {
        let tag = rng2.next() % WIDE;
        let mut payload = Vec::with_capacity(32);
        for _ in 0..16 {
            payload.push((rng2.next() & 0xFF) as u8);
        }
        encode_frame(tag, &payload, &mut out);
    }
    let text_tags: &[u64] = &[1, 42, 300001];
    let text_payloads: &[&str] = &["cleat", "héllo", "γνώθι σεαυτόν"];
    for i in 0..3 {
        encode_text(text_tags[i], text_payloads[i], &mut out);
    }
    // Scan the re-encoded stream: every frame must decode and agree.
    let mut off: usize = 0;
    let mut count: usize = 0;
    while off < out.len() {
        match decode_first(&out[off..]) {
            Err(e) => {
                let m = fe_text(e);
                panic!("H2-FAIL re-scan error near {off}: {m}");
            },
            Ok((f, used)) => {
                check(used >= 3, "re-scan frame size");
                off += used;
                count += 1;
            },
        }
    }
    check(count == (N_OK / 7) as usize + 3, "re-scan frame count");

    // ---- 5. frame_capacity / varint_len cross-check. ----
    let spreads: &[u64] = &[0, 1, 127, 128, 16383, 16384, 0xFFFFFF, 0xFFFFFFFF,
                           18446744073709551615];
    for t in spreads {
        let t = *t;
        for l in LENS_SPREAD {
            let l = *l;
            check(frame_capacity(t, l) == 1 + varint_len(t) + varint_len(l as u64) + l,
                  "capacity arithmetic");
        }
    }

    println!("H2-OK frames={} errors={} bytes={} buckets={}",
             agg.ok_frames, agg.errors, agg.bytes, agg.tag_buckets.len());
}
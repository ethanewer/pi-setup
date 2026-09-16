use std::io;
use veldt_core::kinds::FrameKind;

/// A deterministic pseudo-random generator (xorshift64*).
///
/// One generator per capture makes fixture files reproducible: the same seed
/// always yields the same capture byte for byte (see docs/FRAME_FORMAT.md).
pub struct Rng {
    state: u64,
}

impl Rng {
    /// A generator seeded with `seed`.
    pub fn seeded(seed: u64) -> Rng {
        let mut state = seed;
        if state == 0 {
            state = 0x9E37_79B9_7F4A_7C15;
        }
        // A little avalanche so nearby seeds diverge immediately.
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        Rng { state: state }
    }

    /// The next pseudo-random u64.
    ///
    /// xorshift64 (shifts and xors only): deterministic, and free of the
    /// wrapping-multiply that would panic in a debug build.
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x
    }

    /// The next pseudo-random u32.
    pub fn next_u32(&mut self) -> u32 {
        (self.next_u64() >> 32) as u32
    }

    /// A pseudo-random f64 in [0, 1).
    pub fn next_unit(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1u64 << 53) as f64
    }

    /// A pseudo-random f64 in [lo, hi).
    pub fn next_range(&mut self, lo: f64, hi: f64) -> f64 {
        lo + self.next_unit() * (hi - lo)
    }

    /// A pseudo-random byte.
    pub fn next_byte(&mut self) -> u8 {
        (self.next_u32() & 0xFF) as u8
    }
}

/// Pick a frame kind for a synthetic capture at frame index `i`.
pub fn kind_for_index(rng: &mut Rng, i: u64, total: u64) -> FrameKind {
    if i == 0 {
        return FrameKind::Manifest;
    }
    if i == total - 1 {
        return FrameKind::Tail;
    }
    let roll = rng.next_u32() % 100;
    if roll < 12 {
        FrameKind::Heartbeat
    } else if roll < 22 {
        FrameKind::Alarm
    } else if roll < 34 {
        FrameKind::Status
    } else {
        FrameKind::Sample
    }
}

/// Encode a sample payload: u32 count followed by that many f64 values.
pub fn sample_payload(rng: &mut Rng, count: u32) -> Vec<u8> {
    let mut out: Vec<u8> = Vec::with_capacity(4 + 8 * count as usize);
    out.push((count & 0xFF) as u8);
    out.push(((count >> 8) & 0xFF) as u8);
    out.push(((count >> 16) & 0xFF) as u8);
    out.push(((count >> 24) & 0xFF) as u8);
    for _ in 0..count as u64 {
        let value = rng.next_range(280.0, 340.0); // kelvin
        push_f64_le(&mut out, value);
    }
    out
}

/// A status line payload with plausible station text.
pub fn status_payload(rng: &mut Rng, boot_ms: u64, now_ms: u64) -> Vec<u8> {
    let text = format!(
        "fob=7 uptime={}ms battery={:.2} link=up", now_ms - boot_ms,
        rng.next_range(3.4, 4.1));
    text.as_bytes().to_vec()
}

/// An alarm payload.
pub fn alarm_payload(rng: &mut Rng) -> Vec<u8> {
    let codes: [&str; 4] = ["high-temp", "low-link", "fan-stall", "clock-drift"];
    let code = codes[(rng.next_u32() % 4) as usize];
    format!("{} zone=3", code).as_bytes().to_vec()
}

/// The capture descriptor payload.
pub fn manifest_payload(seed: u64, frames: u64, samples: u32) -> Vec<u8> {
    format!(
        "capture veldt-v1 seed={} frames={} samples/frame={}", seed, frames,
        samples)
        .as_bytes()
        .to_vec()
}

/// Push an f64 as little-endian bytes.
pub fn push_f64_le(out: &mut Vec<u8>, value: f64) {
    let bits = value.to_bits();
    for i in 0..8 {
        out.push(((bits >> (8 * i)) & 0xFF) as u8);
    }
}

/// Read `n` f64 values from the payload start (skip 4-byte count).
pub fn read_f64_le(payload: &[u8], offset: usize) -> io::Result<f64> {
    if offset + 8 > payload.len() {
        return std::result::Result::Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData, "payload too short for an f64"));
    }
    let mut bits: u64 = 0;
    for i in 0..8 {
        bits |= (payload[offset + i] as u64) << (8 * i);
    }
    std::result::Result::Ok(f64::from_bits(bits))
}
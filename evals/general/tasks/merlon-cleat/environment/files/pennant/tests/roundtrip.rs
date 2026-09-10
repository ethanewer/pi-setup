//! Round-trip property tests over pseudo-random frames.

use pennant::{decode_first, encode_frame, frame_capacity};

struct Rng {
    x: u64,
}

impl Rng {
    fn new(seed: u64) -> Rng {
        Rng { x: seed }
    }
    fn next(self: &mut Rng) -> u64 {
        // xorshift64
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        x
    }
}

#[test]
fn roundtrip_pseudo_random() {
    let mut rng = Rng::new(0x5EED);
    let mut sink = Vec::with_capacity(1 << 16);
    for round in 0..2000 {
        let tag = rng.next();
        let len = (rng.next() % 5000) as usize;
        let mut payload = Vec::with_capacity(len);
        for _ in 0..len {
            payload.push((rng.next() & 0xFF) as u8);
        }
        sink.clear();
        let n = encode_frame(tag, &payload, &mut sink);
        check(n == frame_capacity(tag, len), "capacity");
        match decode_first(&sink) {
            Err(e) => {
                let m = fe_text(e);
                panic!("round {round}: decode failed: {m}")
            },
            Ok((f, used)) => {
                check(f.tag == tag, "tag");
                check(f.payload.len() == len, "len");
                check(f.payload == payload, "payload");
                check(used == n, "used");
            }
        }
    }
}

fn check(cond: bool, what: &str) {
    if !cond {
        panic!("{what}");
    }
}

fn fe_text(e: pennant::FrameError) -> &'static str {
    match e {
        pennant::FrameError::BadMagic => "bad magic",
        pennant::FrameError::Truncated => "truncated",
    }
}
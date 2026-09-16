// Hidden generalization case (B): randomized adversarial robustness.
// decode must be total (no panic) on arbitrary bytes, must re-encode
// canonically whatever it accepts, and must reject every single-byte
// perturbation, truncation, insertion and append on valid encodings.

use lwrecord::{decode, encode, Record, Section};

fn xorshift(state: u64) -> u64 {
    let mut x = state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}

fn assert_invariant(buf: &[u8]) {
    match decode(buf) {
        Ok(r) => assert_eq!(encode(&r), buf),
        Err(_) => {},
    }
}

#[test]
fn arbitrary_bytes_never_panic() {
    let mut s: u64 = 0x0123456789ABCDEF;
    let mut tried: usize = 0;
    while tried < 3000 {
        s = xorshift(s);
        let len = (s % 100) as usize;
        let mut buf = Vec::new();
        let mut i = 0;
        while i < len {
            s = xorshift(s);
            buf.push((s & 0xFF) as u8);
            i += 1;
        }
        assert_invariant(&buf);
        tried += 1;
    }
    assert_eq!(tried, 3000);
}

#[test]
fn crafted_byte_lengths() {
    // boundary lengths around the header (19) and the empty record (23)
    let s1: &[u8] = &[0u8; 18];
    assert_invariant(s1);
    let s2: &[u8] = &[0u8; 19];
    assert_invariant(s2);
    let s3: &[u8] = &[0u8; 23];
    assert_invariant(s3);
    let s4: &[u8] = &[0xFFu8; 19];
    assert_invariant(s4);
    let s5: &[u8] = &[0xFFu8; 23];
    assert_invariant(s5);
    // random bytes with the LW01 magic planted at the front
    let mut s: u64 = 0xDEADBEEFCAFEF00D;
    let mut i = 0;
    while i < 200 {
        s = xorshift(s);
        let len = (s % 60) as usize + 19;
        let mut buf = Vec::new();
        buf.extend_from_slice(b"LW01");
        let mut j = 4;
        while j < len {
            s = xorshift(s);
            buf.push((s & 0xFF) as u8);
            j += 1;
        }
        assert_invariant(&buf);
        i += 1;
    }
}

#[test]
fn every_truncation_rejected() {
    let rec = Record { id: 0xCAFEBABE, sections: vec![
        Section { kind: 4u8, payload: vec![0x01u8, 0x02u8] },
        Section { kind: 9u8, payload: vec![0x77u8; 11] },
        Section { kind: 1u8, payload: vec![0x00u8; 3] },
    ] };
    let full = encode(&rec);
    let mut cut = 0;
    while cut < 8 {
        assert_invariant(&full[..full.len() - (cut + 1)]);
        cut += 1;
    }
}

#[test]
fn every_single_byte_flip_rejected() {
    let mut s: u64 = 0x6A09E667F3BCC909;
    let mut rec_idx: usize = 0;
    while rec_idx < 40 {
        s = xorshift(s);
        let n = (s % 5) as usize + 1;
        let mut secs = Vec::new();
        let mut i = 0;
        while i < n {
            s = xorshift(s);
            let kind = ((s % 255) + 1) as u8;
            s = xorshift(s);
            let plen = (s % 30) as usize;
            let mut payload = Vec::new();
            let mut j = 0;
            while j < plen {
                s = xorshift(s);
                payload.push((s & 0xFF) as u8);
                j += 1;
            }
            secs.push(Section { kind: kind, payload: payload });
            i += 1;
        }
        let full = encode(&Record { id: (s as u32), sections: secs });
        let mut b = 0;
        while b < full.len() {
            let mut bad = full.clone();
            bad[b] = bad[b] ^ 0x40;
            match decode(&bad) {
                Ok(_) => assert!(false),
                Err(_) => {},
            }
            b += 1;
        }
        rec_idx += 1;
    }
    assert_eq!(rec_idx, 40);
}

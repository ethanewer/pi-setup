// Integration tests for the lwrecord LW01 codec: fixed format vectors and
// generated property-style checks.  Do not modify.

use lwrecord::{crc32, decode, encode, Record, Section};

fn decode_ok(data: &[u8]) -> Record {
    match decode(data) {
        Ok(r) => r,
        Err(_) => {
            assert!(false);
            Record { id: 0, sections: Vec::new() }
        }
    }
}

fn xorshift(state: u64) -> u64 {
    let mut x = state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}

#[test]
fn crc32_standard_vectors() {
    assert_eq!(crc32(b""), 0);
    assert_eq!(crc32(b"123456789"), 0xCBF43926);
    assert_eq!(crc32(b"a"), 0xE8B7BE43);
}

#[test]
fn fixed_wire_vector() {
    // Record { id: 0x12345678, sections: [ {kind:1, payload:DE AD}, {kind:7, payload:<>} ] }
    let vec = vec![
        0x4Cu8, 0x57u8, 0x30u8, 0x31u8,  // "LW01"
        0x01u8,                           // version
        0x00u8, 0x00u8,                   // flags
        0x78u8, 0x56u8, 0x34u8, 0x12u8,  // id LE
        0x02u8, 0x00u8, 0x00u8, 0x00u8,  // N = 2
        0x02u8, 0x00u8, 0x00u8, 0x00u8,  // P = 2
        0x01u8, 0x02u8, 0x00u8, 0x00u8, 0x00u8, 0xDEu8, 0xADu8,
        0x07u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8,
        0x8Fu8, 0xE5u8, 0x41u8, 0xC9u8,  // crc32 trailer
    ];
    let r = decode_ok(&vec);
    assert_eq!(r.id, 0x12345678);
    assert_eq!(r.sections.len(), 2);
    assert_eq!(r.sections[0].kind, 1);
    assert_eq!(r.sections[0].payload.len(), 2);
    assert_eq!(r.sections[0].payload[0], 0xDE);
    assert_eq!(r.sections[0].payload[1], 0xAD);
    assert_eq!(r.sections[1].kind, 7);
    assert_eq!(r.sections[1].payload.len(), 0);
    // re-encoding reproduces the exact wire bytes
    assert_eq!(encode(&r), vec);
}

#[test]
fn empty_record_wire_vector() {
    let vec = vec![
        0x4Cu8, 0x57u8, 0x30u8, 0x31u8,
        0x01u8, 0x00u8, 0x00u8,
        0x00u8, 0x00u8, 0x00u8, 0x00u8,
        0x00u8, 0x00u8, 0x00u8, 0x00u8,
        0x00u8, 0x00u8, 0x00u8, 0x00u8,
        0x21u8, 0xB7u8, 0xB0u8, 0xDDu8,
    ];
    let r = decode_ok(&vec);
    assert_eq!(r.id, 0);
    assert_eq!(r.sections.len(), 0);
    assert_eq!(encode(&r), vec);
}

#[test]
fn property_roundtrip_generated_records() {
    let mut s: u64 = 0x9E3779B97F4A7C15;
    let mut checked: usize = 0;
    while checked < 400 {
        s = xorshift(s);
        let n = (s % 33) as usize;
        let mut secs = Vec::new();
        let mut p: usize = 0;
        let mut i = 0;
        while i < n {
            s = xorshift(s);
            let kind = ((s % 255) + 1) as u8;
            s = xorshift(s);
            let plen = (s % 41) as usize;
            let mut payload = Vec::new();
            let mut j = 0;
            while j < plen {
                s = xorshift(s);
                payload.push((s & 0xFF) as u8);
                j += 1;
            }
            p += plen;
            secs.push(Section { kind: kind, payload: payload });
            i += 1;
        }
        s = xorshift(s);
        let id = (s as u32) ^ 0x9E3779B9;
        let rec = Record { id: id, sections: secs };
        let enc = encode(&rec);
        // exact size property: 23 + 5N + P
        assert_eq!(enc.len(), 23 + 5 * n + p);
        // determinism
        assert_eq!(encode(&rec), enc);
        // wire round-trip restores every field
        let back = decode_ok(&enc);
        assert_eq!(back.id, rec.id);
        assert_eq!(back.sections.len(), rec.sections.len());
        let mut k = 0;
        while k < rec.sections.len() {
            assert_eq!(back.sections[k].kind, rec.sections[k].kind);
            assert_eq!(back.sections[k].payload.len(), rec.sections[k].payload.len());
            let mut m = 0;
            while m < rec.sections[k].payload.len() {
                assert_eq!(back.sections[k].payload[m], rec.sections[k].payload[m]);
                m += 1;
            }
            k += 1;
        }
        checked += 1;
    }
    assert_eq!(checked, 400);
}

#[test]
fn property_single_byte_perturbation_rejected() {
    // For a valid encoding, flipping any single byte must make decode fail.
    let mut s: u64 = 0x243F6A8885A308D3;
    let mut trials: usize = 0;
    while trials < 120 {
        s = xorshift(s);
        let n = (s % 8) as usize + 1;
        let mut secs = Vec::new();
        let mut i = 0;
        while i < n {
            s = xorshift(s);
            let kind = ((s % 255) + 1) as u8;
            s = xorshift(s);
            let plen = (s % 24) as usize;
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
        let rec = Record { id: (s as u32), sections: secs };
        let enc = encode(&rec);
        let mut b = 0;
        while b < enc.len() {
            let mut bad = enc.clone();
            bad[b] = bad[b] ^ 0x40;
            match decode(&bad) {
                Ok(_) => assert!(false),
                Err(_) => {},
            }
            b += 1;
        }
        trials += 1;
    }
    assert_eq!(trials, 120);
}

#[test]
fn property_max_sections_and_big_kind() {
    let mut secs = Vec::new();
    let mut i = 0;
    while i < 32 {
        let mut payload = Vec::new();
        let mut j = 0;
        while j < 16 {
            payload.push((i as u8) + (j as u8));
            j += 1;
        }
        secs.push(Section { kind: (255u8 - (i as u8)), payload: payload });
        i += 1;
    }
    let rec = Record { id: 0xFFFFFFFF, sections: secs };
    let enc = encode(&rec);
    assert_eq!(enc.len(), 23 + 5 * 32 + 32 * 16);
    let back = decode_ok(&enc);
    assert_eq!(back.sections.len(), 32);
    assert_eq!(back.sections[31].kind, 255 - 31);
    assert_eq!(back.sections[31].payload[0], 31);
}

#[test]
fn property_empty_and_single() {
    let empty = Record { id: 7, sections: Vec::new() };
    let enc = encode(&empty);
    assert_eq!(enc.len(), 23);
    let back = decode_ok(&enc);
    assert_eq!(back.id, 7);
    assert_eq!(back.sections.len(), 0);

    let one = Record { id: 9, sections: vec![Section { kind: 200u8, payload: vec![0xAAu8; 300] }] };
    let e2 = encode(&one);
    assert_eq!(e2.len(), 23 + 5 + 300);
    let b2 = decode_ok(&e2);
    assert_eq!(b2.sections[0].payload.len(), 300);
    assert_eq!(b2.sections[0].payload[299], 0xAA);
}

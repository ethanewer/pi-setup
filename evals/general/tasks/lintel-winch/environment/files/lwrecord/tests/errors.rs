// Integration tests: decode error classification for malformed, truncated and
// adversarial inputs.  Do not modify.

use lwrecord::{crc32, decode, encode, Record, Section};

// Stable codes mirroring the documented error table, so a test can assert the
// exact variant decode chose.
fn is_variant(e: lwrecord::FormatError) -> u8 {
    match e {
        lwrecord::FormatError::Truncated => 1,
        lwrecord::FormatError::BadMagic => 2,
        lwrecord::FormatError::UnsupportedVersion => 3,
        lwrecord::FormatError::BadFlags => 4,
        lwrecord::FormatError::TooManySections => 5,
        lwrecord::FormatError::InvalidSectionType => 6,
        lwrecord::FormatError::TrailingBytes => 7,
        lwrecord::FormatError::PayloadMismatch => 8,
        lwrecord::FormatError::BadChecksum => 9,
    }
}

fn expect_err(data: &[u8], want: u8) {
    match decode(data) {
        Err(e) => assert_eq!(is_variant(e), want),
        Ok(_) => assert!(false),
    }
}

// recompute and rewrite the 4-byte trailer so the buffer has a single defect
fn fix_trailer(buf: &[u8]) -> Vec<u8> {
    let n = buf.len();
    let cb = crc32(&buf[..n - 4]).to_le_bytes();
    let mut out = Vec::with_capacity(n);
    let mut i = 0;
    while i < n - 4 {
        out.push(buf[i]);
        i += 1;
    }
    let mut j = 0;
    while j < 4 {
        out.push(cb[j]);
        j += 1;
    }
    out
}

fn sample() -> Record {
    Record { id: 0xA1B2C3D4, sections: vec![
        Section { kind: 3u8, payload: vec![1u8, 2u8, 3u8, 4u8, 5u8] },
        Section { kind: 9u8, payload: vec![0xFFu8, 0x00u8] },
    ] }
}

#[test]
fn truncated() {
    let short4: &[u8] = &[0x4Cu8, 0x57u8];
    expect_err(short4, 1);
    expect_err(b"LW01", 1);
    let full = encode(&sample());
    expect_err(&full[..18], 1);  // header cut short
    expect_err(&full[..22], 1);  // first section header cut short
    // one section with a payload of 10 bytes, cut mid-payload
    let one = encode(&Record { id: 1, sections: vec![
        Section { kind: 5u8, payload: vec![0x11u8; 10] }] });
    expect_err(&one[..33], 1);   // 19 + 5 + 9 of the payload
}

#[test]
fn bad_magic() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[0] = 0x00;
    expect_err(&bad, 2);
    let mut bad2 = full.clone();
    bad2[3] = b'X';
    expect_err(&bad2, 2);
    let mut bad3 = full.clone();
    bad3[0] = 0x00;
    bad3[4] = 9;
    bad3[5] = 1;     // wrong magic + wrong version + bad flags: magic wins
    expect_err(&bad3, 2);
}

#[test]
fn unsupported_version() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[4] = 0;
    expect_err(&fix_trailer(&bad), 3);
    let mut bad2 = full.clone();
    bad2[4] = 2;
    expect_err(&fix_trailer(&bad2), 3);
    let mut bad3 = full.clone();
    bad3[4] = 255;
    expect_err(&fix_trailer(&bad3), 3);
}

#[test]
fn bad_flags() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[5] = 1;
    expect_err(&fix_trailer(&bad), 4);
    let mut bad2 = full.clone();
    bad2[6] = 0xFF;
    expect_err(&fix_trailer(&bad2), 4);
    let mut bad3 = full.clone();
    bad3[5] = 0xFF;
    bad3[6] = 0xFF;
    expect_err(&fix_trailer(&bad3), 4);
}

#[test]
fn too_many_sections() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[11] = 33;
    expect_err(&fix_trailer(&bad), 5);
    let mut bad2 = full.clone();
    bad2[14] = 0x80;
    expect_err(&fix_trailer(&bad2), 5);
}

#[test]
fn invalid_section_type() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[19] = 0;
    expect_err(&fix_trailer(&bad), 6);
    let rec = Record { id: 1, sections: vec![Section { kind: 0u8, payload: vec![9u8] }] };
    expect_err(&encode(&rec), 6);
    let rec2 = Record { id: 1, sections: vec![
        Section { kind: 2u8, payload: vec![1u8] },
        Section { kind: 0u8, payload: Vec::new() },
        Section { kind: 4u8, payload: vec![2u8] }] };
    let mut bad2 = encode(&rec2);
    // the kind=0 section is the second one: offset 19 + 6 = 25
    expect_err(&fix_trailer(&bad2), 6);
}

#[test]
fn trailing_bytes() {
    let full = encode(&sample());
    let n = full.len();
    // garbage inserted between body and trailer
    let mut bad = Vec::new();
    bad.extend_from_slice(&full[..n - 4]);
    bad.push(0xA5);
    bad.push(0xA6);
    bad.push(0xA7);
    bad.extend_from_slice(&full[n - 4..]);
    expect_err(&bad, 7);
    // garbage appended after the trailer
    let mut bad2 = full.clone();
    bad2.push(0x11);
    bad2.push(0x22);
    expect_err(&bad2, 7);
    // garbage appended after the trailer to an empty record
    let empty = encode(&Record { id: 0, sections: Vec::new() });
    let mut bad3 = empty.clone();
    bad3.push(0x01);
    expect_err(&bad3, 7);
}

#[test]
fn payload_mismatch() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[15] = 19;     // header P inflated
    expect_err(&fix_trailer(&bad), 8);
    let mut bad2 = full.clone();
    bad2[15] = 1;     // header P deflated
    expect_err(&fix_trailer(&bad2), 8);
    let empty = encode(&Record { id: 5, sections: Vec::new() });
    let mut bad3 = empty.clone();
    bad3[15] = 3;     // P nonzero with zero sections
    expect_err(&fix_trailer(&bad3), 8);
    let mut bad4 = full.clone();
    bad4[18] = 0x04;  // P = 0x04000000
    expect_err(&fix_trailer(&bad4), 8);
}

#[test]
fn bad_checksum() {
    let full = encode(&sample());
    let mut bad = full.clone();
    bad[26] = bad[26] ^ 0x01;   // flip a payload byte, trailer left stale
    expect_err(&bad, 9);
    let mut bad2 = full.clone();
    bad2[7] = bad2[7] ^ 0x01;   // flip a header id byte, trailer left stale
    expect_err(&bad2, 9);
    let n = full.len();
    let mut bad3 = full.clone();
    bad3[n - 1] = bad3[n - 1] ^ 0x80;  // corrupt the trailer itself
    expect_err(&bad3, 9);
    let mut bad4 = full.clone();
    bad4[n - 4] = 0xFF;
    expect_err(&bad4, 9);
}

#[test]
fn error_precedence_is_locked() {
    // Pins the documented rule: when several defects coexist, the one listed
    // earliest in the error table is reported.
    let full = encode(&sample());
    let mut a = full.clone();
    a[0] = 0x55;
    a[4] = 7;
    expect_err(&a, 2);                      // magic over version
    let mut b = full.clone();
    b[4] = 3;
    b[5] = 1;
    expect_err(&fix_trailer(&b), 3);        // version over flags
    let mut c = full.clone();
    c[5] = 1;
    c[11] = 33;
    expect_err(&fix_trailer(&c), 4);        // flags over section count
    let mut d = full.clone();
    d[11] = 33;
    let mut t = fix_trailer(&d);
    t.resize(t.len() - 4, 0);               // also truncated now
    expect_err(&t, 5);                      // count over truncation
    let mut e = full.clone();
    e[19] = 0;
    e.push(0x99);                           // also trailing bytes
    expect_err(&e, 6);                      // bad kind over trailing bytes
    let mut f = full.clone();
    f[15] = 0;
    f.push(0x99);                           // also trailing bytes
    expect_err(&f, 7);                      // trailing over payload mismatch
    let mut g = full.clone();
    g[15] = 8;                              // P wrong (real sum is 7), stale trailer
    expect_err(&g, 8);                      // mismatch beats checksum
}

// Hidden generalization case (A): malformed / truncated / adversarial inputs
// beyond the visible suite.  Mounted by the verifier; do not modify.

use lwrecord::{crc32, decode, encode, Record, Section};

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

fn expect_ok(data: &[u8]) {
    match decode(data) {
        Ok(_) => {},
        Err(_) => assert!(false),
    }
}

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

fn header_bytes(n_sections: u8, p_lo: u8) -> Vec<u8> {
    // 19-byte header builder: id fixed, N and P low bytes given
    let mut h = Vec::new();
    h.extend_from_slice(b"LW01");
    h.push(1);
    h.push(0);
    h.push(0);
    h.push(0x11);
    h.push(0x22);
    h.push(0x33);
    h.push(0x44);
    h.push(n_sections);
    h.push(0);
    h.push(0);
    h.push(0);
    h.push(p_lo);
    h.push(0);
    h.push(0);
    h.push(0);
    h
}

#[test]
fn header_with_no_body() {
    // a structurally perfect 19-byte header is still Truncated (min 23 bytes)
    let h = header_bytes(0, 0);
    expect_err(&fix_trailer(&h), 1);
    let h2 = header_bytes(1, 0);
    expect_err(&fix_trailer(&h2), 1);
    let h3 = header_bytes(32, 0);
    expect_err(&fix_trailer(&h3), 1);
}

#[test]
fn mid_section_cuts() {
    // section header present but payload incompletely transmitted
    let one = encode(&Record { id: 1, sections: vec![
        Section { kind: 5u8, payload: vec![0x11u8; 10] }] });
    let mut i = 20;
    while i < 37 {
        expect_err(&one[..i], 1);
        i += 1;
    }
}

#[test]
fn plen_overrun_into_trailer() {
    let one = encode(&Record { id: 1, sections: vec![
        Section { kind: 5u8, payload: vec![0x11u8; 10] }] });
    expect_err(&one[..33], 1);  // 10-byte payload cut to 9
    expect_err(&one[..34], 1);  // plen says 10 but only ends at trailer start
}

#[test]
fn slice_into_payload_region() {
    // take a valid 24-byte window that starts mid-header and ends mid-body;
    // magic check must reject first
    let full = encode(&Record { id: 0xAA, sections: vec![
        Section { kind: 1u8, payload: vec![0x42u8; 6] }] });
    let win: &[u8] = &full[3..27];
    expect_err(win, 2);
}

#[test]
fn zero_and_high_kinds() {
    // kind 0 anywhere in the section list is rejected...
    let rec = Record { id: 1, sections: vec![
        Section { kind: 2u8, payload: vec![1u8] },
        Section { kind: 0u8, payload: Vec::new() },
        Section { kind: 4u8, payload: vec![2u8] }] };
    expect_err(&encode(&rec), 6);
    // ...but every nonzero kind (1 and 255) is accepted
    let ok1 = Record { id: 2, sections: vec![Section { kind: 1u8, payload: Vec::new() }] };
    expect_ok(&encode(&ok1));
    let ok2 = Record { id: 3, sections: vec![Section { kind: 255u8, payload: vec![0u8; 5] }] };
    expect_ok(&encode(&ok2));
}

#[test]
fn empty_record_edges() {
    let empty = encode(&Record { id: 0, sections: Vec::new() });
    expect_ok(&empty);
    // one stray byte after the trailer
    let mut a = empty.clone();
    a.push(0x00);
    expect_err(&a, 7);
    // P nonzero with no sections at all
    let mut b = empty.clone();
    b[15] = 1;
    expect_err(&fix_trailer(&b), 8);
}

#[test]
fn adversarial_buffers() {
    // all-zero buffer at varying lengths: bad magic (or truncated when tiny)
    let zeros: &[u8] = &[0u8; 64];
    expect_err(zeros, 2);
    expect_err(&zeros[..10], 1);
    // "LW" prefix with garbage after
    let lw: &[u8] = &[b'L', b'W', 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                     0x00, 0x00, 0x00, 0x00];
    expect_err(lw, 2);
    // correct magic + version, garbage after: flags check or structural error
    let hdr: &[u8] = &[b'L', b'W', b'0', b'1', 0x01, 0x00, 0x00,
                       0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                       0x00, 0x00, 0x00, 0x00, 0x00];
    expect_err(&fix_trailer(&hdr), 1);   // only 19 bytes: no body, no trailer
}

#[test]
fn flags_high_bits() {
    let full = encode(&Record { id: 9, sections: Vec::new() });
    let mut a = full.clone();
    a[6] = 0x80;
    expect_err(&fix_trailer(&a), 4);
    let mut b = full.clone();
    b[5] = 0x01;
    b[6] = 0xFE;
    expect_err(&fix_trailer(&b), 4);
}

#[test]
fn count_overflow_words() {
    let full = encode(&Record { id: 9, sections: Vec::new() });
    let mut a = full.clone();
    a[11] = 0xFF;
    a[12] = 0xFF;
    a[13] = 0xFF;
    a[14] = 0xFF;
    expect_err(&fix_trailer(&a), 5);
}

#[test]
fn trailer_swap_regions() {
    // swap the trailer with the last 4 payload bytes: the walk still reaches
    // a full record, but the checksum over the shifted body must not match
    let full = encode(&Record { id: 0x11, sections: vec![
        Section { kind: 2u8, payload: vec![0x33u8; 8] }] });
    let n = full.len();
    let mut bad = Vec::new();
    bad.extend_from_slice(&full[..28]);              // header + payload[0..4]
    bad.extend_from_slice(&full[n - 4..]);           // old trailer moved into payload
    bad.extend_from_slice(&full[28..n - 4]);         // old payload bytes become trailer
    expect_err(&bad, 9);
}

// Integration tests for the beaconpack codec.  Do not weaken or delete these.
use beaconpack::{compress, decompress, roundtrip_ok};

#[test]
fn empty_roundtrip() {
    assert!(roundtrip_ok(&[]));
}

#[test]
fn single_byte() {
    assert!(roundtrip_ok(&[9]));
}

#[test]
fn text_roundtrip() {
    let d = b"granite beacon alluvial swath";
    assert!(roundtrip_ok(d));
}

#[test]
fn long_run_compresses() {
    let d = vec![0x77u8; 300];
    assert!(roundtrip_ok(&d));
    assert!(compress(&d).len() < d.len());
}

#[test]
fn mixed_roundtrip() {
    let mut d = Vec::new();
    for _ in 0..30 {
        d.extend_from_slice(b"abcabcabcbca");
    }
    assert!(roundtrip_ok(&d));
}

#[test]
fn locked_wire_format() {
    // input "zzzz" -> C5 04 00 00 00 | run header (n-1)=3 | b'z'
    let c = compress(b"zzzz");
    assert_eq!(c, vec![0xC5, 4, 0, 0, 0, 3, b'z']);
}

#[test]
fn reject_bad_magic() {
    assert!(decompress(&[0x00]).is_err());
    let mut bad = compress(b"ab");
    bad[0] = 0xFF;
    assert!(decompress(&bad).is_err());
}

#[test]
fn reject_overshoot() {
    // header declares 1 byte but the run stream yields two
    let frame = vec![0xC5, 1, 0, 0, 0, 1, b'a', b'b'];
    assert!(decompress(&frame).is_err());
}

#[test]
fn reject_truncated() {
    // header declares 8 bytes but the run stream is empty
    let frame = vec![0xC5, 8, 0, 0, 0];
    assert!(decompress(&frame).is_err());
}
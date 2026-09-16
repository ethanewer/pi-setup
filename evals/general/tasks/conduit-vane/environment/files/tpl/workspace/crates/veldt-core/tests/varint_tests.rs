use veldt_core::bytes::{BytesMut, Cursor};
use veldt_core::varint;

fn round_unsigned(v: u64) {
    let mut buf = BytesMut::empty();
    varint::encode_unsigned(&mut buf, v);
    let mut c = Cursor::over(buf.as_slice());
    let back = varint::decode_unsigned(&mut c).unwrap();
    assert!(back == v);
    assert!(c.is_exhausted());
    assert!(varint::encoded_len(v) == buf.len());
}

fn round_signed(v: i64) {
    let mut buf = BytesMut::empty();
    varint::encode_signed(&mut buf, v);
    let mut c = Cursor::over(buf.as_slice());
    let back = varint::decode_signed(&mut c).unwrap();
    assert!(back == v);
    assert!(c.is_exhausted());
    assert!(varint::encoded_len_signed(v) == buf.len());
}

#[test]
fn unsigned_edge_values() {
    round_unsigned(0);
    round_unsigned(1);
    round_unsigned(127);
    round_unsigned(128);
    round_unsigned(16_383);
    round_unsigned(16_384);
    round_unsigned(0xFFFF_FFFF);
    round_unsigned(u64::MAX);
    round_unsigned(u64::MAX - 1);
}

#[test]
fn signed_edge_values() {
    round_signed(0);
    round_signed(1);
    round_signed(-1);
    round_signed(63);
    round_signed(64);
    round_signed(-64);
    round_signed(-65);
    round_signed(i64::MAX);
    round_signed(i64::MIN);
}

#[test]
fn tiny_values_are_one_byte() {
    let mut buf = BytesMut::empty();
    varint::encode_unsigned(&mut buf, 0);
    assert!(buf.len() == 1);
    buf.clear();
    varint::encode_signed(&mut buf, -1);
    assert!(buf.len() == 1);
}

#[test]
fn oversized_encoded_value_is_rejected() {
    // 11 continuation groups: over the 10-byte ceiling, so it must error.
    let mut raw: Vec<u8> = Vec::new();
    for _ in 0..10 {
        raw.push(0x80);
    }
    raw.push(0x01);
    let mut c = Cursor::over(raw.as_slice());
    assert!(varint::decode_unsigned(&mut c).is_err());
}

#[test]
fn truncated_encoding_is_rejected() {
    let raw: [u8; 3] = [0x80, 0x80, 0x80];
    let mut c = Cursor::over(raw.as_slice());
    assert!(varint::decode_unsigned(&mut c).is_err());
}

#[test]
fn overflow_is_rejected() {
    // 10 groups where group 10 carries more than one bit: overflows u64.
    let mut raw: Vec<u8> = Vec::new();
    for _ in 0..9 {
        raw.push(0xFF);
    }
    raw.push(0xFF);
    let mut c = Cursor::over(raw.as_slice());
    assert!(varint::decode_unsigned(&mut c).is_err());
}

#[test]
fn nearby_lengths_are_distinct() {
    assert!(varint::encoded_len(127) == 1);
    assert!(varint::encoded_len(128) == 2);
    assert!(varint::encoded_len(u64::MAX) == 10);
}
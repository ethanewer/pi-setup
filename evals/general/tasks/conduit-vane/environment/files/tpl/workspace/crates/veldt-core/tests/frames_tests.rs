use veldt_core::bytes::{BytesMut, Cursor};
use veldt_core::frame::{Frame, MAGIC};
use veldt_core::kinds::FrameKind;

fn sample(kind: FrameKind, seq: u32, ts: u64, payload: Vec<u8>) -> Frame {
    Frame::new(kind, seq, ts, payload)
}

#[test]
fn encode_decode_roundtrip() {
    let frame = sample(
        FrameKind::Sample, 7, 1_234_567, [0x01, 0x02, 0x03, 0x04].to_vec());
    let bytes = frame.encode();
    let back = Frame::decode_slice(bytes.as_slice()).unwrap();
    assert!(back.kind() == FrameKind::Sample);
    assert!(back.seq() == 7);
    assert!(back.ts_ms() == 1_234_567);
    assert!(back.payload() == [0x01, 0x02, 0x03, 0x04].as_slice());
}

#[test]
fn empty_payload_frame_is_22_bytes() {
    let frame = sample(FrameKind::Tail, 0, 0, Vec::<u8>::new());
    let bytes = frame.encode();
    assert!(bytes.len() == 22);
    assert!(frame.length_bytes() == 22);
}

#[test]
fn decode_rejects_bad_magic() {
    let mut bytes = sample(FrameKind::Manifest, 1, 2, [].to_vec()).encode();
    bytes[0] = 0x00;
    assert!(Frame::decode_slice(bytes.as_slice()).is_err());
}

#[test]
fn decode_rejects_corrupted_payload() {
    let mut bytes = sample(FrameKind::Status, 2, 3, [0x41, 0x42, 0x43].to_vec()).encode();
    bytes[19] ^= 0xFF;
    assert!(Frame::decode_slice(bytes.as_slice()).is_err());
}

#[test]
fn decode_rejects_truncation() {
    let bytes = sample(FrameKind::Alarm, 4, 5, [0x01, 0x02, 0x03, 0x04, 0x05].to_vec()).encode();
    let cut = bytes[0..bytes.len() - 3].to_vec();
    let cut_s = cut.as_slice();
    assert!(Frame::decode_slice(cut_s).is_err());
}

#[test]
fn decode_rejects_unknown_kind_tag() {
    let mut bytes = sample(FrameKind::Heartbeat, 6, 7, [].to_vec()).encode();
    bytes[1] = 0x7F;
    assert!(Frame::decode_slice(bytes.as_slice()).is_err());
}

#[test]
fn kind_tags_are_stable_protocol_values() {
    assert!(FrameKind::Heartbeat.tag() == 0x01);
    assert!(FrameKind::Status.tag() == 0x02);
    assert!(FrameKind::Sample.tag() == 0x03);
    assert!(FrameKind::Alarm.tag() == 0x04);
    assert!(FrameKind::Manifest.tag() == 0x05);
    assert!(FrameKind::Tail.tag() == 0x06);
    assert!(FrameKind::from_tag(0x03).is_some());
    assert!(FrameKind::from_tag(0xFF).is_none());
    assert!(FrameKind::from_tag(0x03).unwrap() == FrameKind::Sample);
}

#[test]
fn long_payload_roundtrips() {
    let mut payload = Vec::with_capacity(300_000);
    for i in 0..300_000 {
        payload.push((i % 256) as u8);
    }
    let frame = sample(FrameKind::Sample, 88, 9_999, payload);
    let bytes = frame.encode();
    let back = Frame::decode_slice(bytes.as_slice()).unwrap();
    assert!(back.payload().len() == 300_000);
    assert!(back.payload()[0] == 0);
    assert!(back.payload()[299_999] == (299_999 % 256) as u8);
}

#[test]
fn magic_byte_matches_docs() {
    assert!(MAGIC == 0xA6);
}
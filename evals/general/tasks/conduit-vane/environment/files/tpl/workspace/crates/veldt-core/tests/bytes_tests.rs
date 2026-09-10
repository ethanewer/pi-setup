use veldt_core::bytes::{BytesMut, Cursor};

#[test]
fn push_and_read_roundtrip() {
    let mut buf = BytesMut::empty();
    buf.push_u8(0x01);
    buf.push_u16_le(0x0203);
    buf.push_u32_le(0x0405_0607);
    buf.push_u64_le(0x0809_0A0B_0C0D_0E0F);
    assert!(buf.len() == 15);
    let mut c = Cursor::over(buf.as_slice());
    assert!(c.read_u8().unwrap() == 0x01);
    assert!(c.read_u16_le().unwrap() == 0x0203);
    assert!(c.read_u32_le().unwrap() == 0x0405_0607);
    assert!(c.read_u64_le().unwrap() == 0x0809_0A0B_0C0D_0E0F);
    assert!(c.is_exhausted());
}

#[test]
fn cursor_errors_at_end() {
    let data: [u8; 2] = [0x11, 0x22];
    let mut c = Cursor::over(data.as_slice());
    assert!(c.read_u8().is_ok());
    assert!(c.read_u8().is_ok());
    assert!(c.read_u8().is_err());
    assert!(c.read_u16_le().is_err());
    assert!(c.read_u32_le().is_err());
}

#[test]
fn partial_reads_are_truncated() {
    let data: [u8; 5] = [0x01, 0x02, 0x03, 0x04, 0x05];
    let mut c = Cursor::over(data.as_slice());
    assert!(c.read_u32_le().is_ok());
    assert!(c.read_u16_le().is_err());
    assert!(c.peek_u8().is_err());
}

#[test]
fn skip_and_slices() {
    let data: [u8; 8] = [0, 1, 2, 3, 4, 5, 6, 7];
    let mut c = Cursor::over(data.as_slice());
    assert!(c.skip(3).is_ok());
    assert!(c.pos() == 3);
    let s = c.read_bytes(2).unwrap();
    assert!(s.len() == 2 && s[0] == 3 && s[1] == 4);
    assert!(c.remaining() == 3);
    assert!(c.skip(4).is_err());
    c.rewind();
    assert!(c.pos() == 0);
}

#[test]
fn growable_push_many() {
    let mut buf = BytesMut::empty();
    for i in 0..10_000 {
        buf.push_u8((i % 251) as u8);
    }
    assert!(buf.len() == 10_000);
    buf.truncate(7);
    assert!(buf.len() == 7);
    buf.clear();
    assert!(buf.is_empty());
}

#[test]
fn slices_are_shared_not_copied() {
    let src = [1, 2, 3];
    let mut buf = BytesMut::from_vec(src.to_vec());
    buf.push_u8(4);
    assert!(buf.as_slice().len() == 4);
    buf.as_mut_slice()[0] = 99;
    assert!(buf.as_slice()[0] == 99);
}

#[test]
fn vec_push() {
    let mut buf = BytesMut::empty();
    let extra = [9, 8, 7, 6];
    buf.push_slice(extra.as_slice());
    assert!(buf.len() == 4);
    buf.push_bytes(extra.as_slice());
    assert!(buf.len() == 8);
}
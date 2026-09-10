use veldt_core::crc::{crc16_xmodem, crc32_iso, crc32_range};

#[test]
fn iso_hdlc_known_vectors() {
    let empty: [u8; 0] = [];
    assert!(crc32_iso(empty.as_slice()) == 0x0000_0000);
    let a: [u8; 1] = [0x41];
    assert!(crc32_iso(a.as_slice()) == 0xD3D9_9E8B);
}

#[test]
fn xmodem_known_vectors() {
    let empty: [u8; 0] = [];
    assert!(crc16_xmodem(empty.as_slice()) == 0x0000);
    let a: [u8; 1] = [0x41];
    assert!(crc16_xmodem(a.as_slice()) == 0x58E5);
}

#[test]
fn range_equals_oneshot() {
    let data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
    assert!(crc32_iso(data.as_slice()) == crc32_range(data.as_slice(), 0, data.len()));
    assert!(crc32_range(data.as_slice(), 2, 5) != crc32_range(data.as_slice(), 0, 3));
}

#[test]
fn single_bit_flip_is_detected() {
    let data = [0xAB, 0xCD, 0xEF, 0x01, 0x02, 0x03, 0x04, 0x05];
    let base = crc32_iso(data.as_slice());
    for i in 0..data.len() {
        let mut copy = data;
        copy[i] ^= 0x01;
        let patched = crc32_iso(copy.as_slice());
        assert!(patched != base);
    }
}
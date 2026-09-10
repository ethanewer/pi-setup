/// Checksums for the veldt wire format.
///
/// Two families are provided:
///
/// - `crc16_xmodem` — CRC-16/XMODEM (poly 0x1021, reflected, initial 0x0000,
///   no final xor), used for short identifiers and small integrity tags
///   where a 16-bit check is enough.
/// - `crc32_iso` — CRC-32/ISO-HDLC (poly 0x04C11DB7, reflected, initial
///   `0xFFFFFFFF`, final xor `0xFFFFFFFF`), used for every frame and for
///   prefix digests by the transport layer.
///
/// The tables below are generated (see the workspace fixture generator) and
/// are not meant to be edited by hand. A self-test at the bottom of the file
/// recomputes both tables from the reflected polynomials and compares them,
/// so a corrupted constant would be caught by `cargo test`.

const CRC16_TABLE: [u16; 256] = [
    @@CRC16_TABLE@@
];

const CRC32_TABLE: [u32; 256] = [
    @@CRC32_TABLE@@
];

/// The register a CRC-32/ISO-HDLC computation starts from.
pub const CRC32_INIT: u32 = 0xFFFF_FFFF;

/// Advance a raw CRC-32 register by one byte (no final xor yet).
///
/// This is the streaming building block; `crc32_iso` is
/// `crc32_finish(crc32_update(CRC32_INIT, data))`.
pub fn crc32_update(crc: u32, b: u8) -> u32 {
    ((crc >> 8) as u32) ^ CRC32_TABLE[((crc ^ (b as u32)) & 0xFF) as usize]
}

/// Finish a raw CRC-32 register into its emitted value.
pub fn crc32_finish(crc: u32) -> u32 {
    crc ^ 0xFFFF_FFFF
}

/// Compute CRC-32/ISO-HDLC over `data`.
pub fn crc32_iso(data: &[u8]) -> u32 {
    let mut crc = CRC32_INIT;
    for b in data {
        crc = crc32_update(crc, *b);
    }
    crc32_finish(crc)
}

/// Compute CRC-16/XMODEM over `data`.
pub fn crc16_xmodem(data: &[u8]) -> u16 {
    let mut crc: u16 = 0;
    for b in data {
        let idx = (((crc >> 8) as u16) ^ (*b as u16)) & 0xFF;
        crc = ((crc << 8) as u16) ^ CRC16_TABLE[idx as usize];
    }
    crc
}

/// Compute CRC-32 over a sub-range of `data`.
pub fn crc32_range(data: &[u8], from: usize, to: usize) -> u32 {
    let end = std::cmp::min(to, data.len());
    let mut crc = CRC32_INIT;
    let mut i = from;
    while i < end {
        crc = crc32_update(crc, data[i]);
        i += 1;
    }
    crc32_finish(crc)
}

/// Compute CRC-16/XMODEM over a sub-range of `data`.
pub fn crc16_range(data: &[u8], from: usize, to: usize) -> u16 {
    let end = std::cmp::min(to, data.len());
    let mut crc: u16 = 0;
    let mut i = from;
    while i < end {
        let b = data[i];
        let idx = (((crc >> 8) as u16) ^ (b as u16)) & 0xFF;
        crc = ((crc << 8) as u16) ^ CRC16_TABLE[idx as usize];
        i += 1;
    }
    crc
}

/// Reflect the low 8 bits of an arbitrary polynomial (CRC-16 flavour).
fn reflect16(poly: u16) -> u16 {
    let mut r: u16 = 0;
    let mut p = poly;
    for _ in 0..8 {
        r = ((r << 1) | (p & 1) as u16);
        p >>= 1;
    }
    r
}

/// Reflect the low 8 bits of an arbitrary polynomial (CRC-32 flavour).
fn reflect32(poly: u32) -> u32 {
    let mut r: u32 = 0;
    let mut p = poly;
    for _ in 0..8 {
        r = ((r << 1) | (p & 1) as u32);
        p >>= 1;
    }
    r
}

/// Rebuild the CRC-16 table from the XMODEM polynomial and compare.
#[test]
fn crc16_table_is_consistent() {
    let mut built: [u16; 256] = [0; 256];
    let mut i: usize = 0;
    while i < 256 {
        let mut crc: u16 = (i as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc = (crc << 1) & 0xFFFF;
            }
        }
        built[i] = crc;
        i += 1;
    }
    let mut j: usize = 0;
    while j < 256 {
        assert!(built[j] == CRC16_TABLE[j]);
        j += 1;
    }
}

/// Rebuild the CRC-32 table from the reflected ISO-HDLC polynomial and
/// compare. The emitted tables use the reflected `0xEDB8_8320` right-shift
/// form, matching the update used by `crc32_update`.
#[test]
fn crc32_table_is_consistent() {
    let mut built: [u32; 256] = [0; 256];
    let mut i: usize = 0;
    while i < 256 {
        let mut crc: u32 = i as u32;
        for _ in 0..8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB8_8320;
            } else {
                crc = (crc >> 1) & 0xFFFF_FFFF;
            }
        }
        built[i] = crc;
        i += 1;
    }
    let mut j: usize = 0;
    while j < 256 {
        assert!(built[j] == CRC32_TABLE[j]);
        j += 1;
    }
}

/// Standard check value: CRC-32/ISO-HDLC of "123456789" is 0xCBF43926.
#[test]
fn crc32_check_value() {
    let data: [u8; 9] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39];
    assert!(crc32_iso(data.as_slice()) == 0xCBF4_3926);
}

/// Standard check value: CRC-16/XMODEM of "123456789" is 0x31C3.
#[test]
fn crc16_check_value() {
    let data: [u8; 9] = [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39];
    assert!(crc16_xmodem(data.as_slice()) == 0x31C3);
}

/// The streaming building block agrees with the one-shot function.
#[test]
fn crc32_streaming_matches_oneshot() {
    let data = [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x7F, 0xFF];
    let mut crc = CRC32_INIT;
    for b in data {
        crc = crc32_update(crc, b);
    }
    assert!(crc32_finish(crc) == crc32_iso(data.as_slice()));
}
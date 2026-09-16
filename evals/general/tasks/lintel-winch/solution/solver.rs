//! lwrecord — container codec for the LW01 binary record format (version 1).
//!
//!   header (19 bytes): "LW01" | version=1 (u8) | flags (u16) | record id (u32)
//!                      | section count N (u32, 0..=32) | payload length P (u32)
//!   body: N sections, each  kind (u8, 1..=255) | plen (u32) | plen payload bytes
//!   trailer (4 bytes): CRC-32 over every byte except the trailer itself
//!
//! The decoder is total: every input yields either an Ok or a FormatError.

pub enum FormatError {
    Truncated,
    BadMagic,
    UnsupportedVersion,
    BadFlags,
    TooManySections,
    InvalidSectionType,
    TrailingBytes,
    PayloadMismatch,
    BadChecksum,
}

pub struct Section {
    pub kind: u8,
    pub payload: Vec<u8>,
}

pub struct Record {
    pub id: u32,
    pub sections: Vec<Section>,
}

fn crc32_prefix(data: &[u8], end: usize) -> u32 {
    let mut crc: u32 = 0xFFFFFFFF;
    let mut i = 0;
    while i < end {
        crc ^= data[i] as u32;
        let mut k = 0;
        while k < 8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
            k += 1;
        }
        i += 1;
    }
    !crc
}

pub fn crc32(data: &[u8]) -> u32 {
    crc32_prefix(data, data.len())
}

pub fn encode(record: &Record) -> Vec<u8> {
    let n = record.sections.len();
    let mut total_payload: u64 = 0;
    let mut i = 0;
    while i < n {
        total_payload += record.sections[i].payload.len() as u64;
        i += 1;
    }
    let mut out = Vec::with_capacity(23 + 5 * n + (total_payload as usize));
    out.extend_from_slice(b"LW01");
    out.push(1);
    out.push(0);
    out.push(0);
    out.extend_from_slice(&record.id.to_le_bytes());
    out.extend_from_slice(&(n as u32).to_le_bytes());
    out.extend_from_slice(&(total_payload as u32).to_le_bytes());
    i = 0;
    while i < n {
        out.push(record.sections[i].kind);
        out.extend_from_slice(&(record.sections[i].payload.len() as u32).to_le_bytes());
        out.extend_from_slice(&record.sections[i].payload);
        i += 1;
    }
    let trailer = crc32_prefix(&out, out.len());
    out.extend_from_slice(&trailer.to_le_bytes());
    out
}

pub fn decode(data: &[u8]) -> Result<Record, FormatError> {
    if data.len() < 19 {
        return Err(FormatError::Truncated);
    }
    if data[0] != b'L' || data[1] != b'W' || data[2] != b'0' || data[3] != b'1' {
        return Err(FormatError::BadMagic);
    }
    if data[4] != 1 {
        return Err(FormatError::UnsupportedVersion);
    }
    let flags: u32 = (data[5] as u32) | ((data[6] as u32) << 8);
    if flags != 0 {
        return Err(FormatError::BadFlags);
    }
    let rid = u32::from_le_bytes([data[7], data[8], data[9], data[10]]);
    let n = u32::from_le_bytes([data[11], data[12], data[13], data[14]]);
    if n > 32 {
        return Err(FormatError::TooManySections);
    }
    let declared_p = u32::from_le_bytes([data[15], data[16], data[17], data[18]]) as u64;
    let n_usize = n as usize;
    if data.len() < 23 + 5 * n_usize {
        return Err(FormatError::Truncated);
    }
    let mut pos: usize = 19;
    let mut sections = Vec::new();
    let mut sum_p: u64 = 0;
    let mut idx = 0;
    while idx < n_usize {
        if pos + 5 > data.len() - 4 {
            return Err(FormatError::Truncated);
        }
        let kind = data[pos];
        if kind == 0 {
            return Err(FormatError::InvalidSectionType);
        }
        let plen = u32::from_le_bytes([data[pos + 1], data[pos + 2], data[pos + 3], data[pos + 4]]) as u64;
        if plen > (data.len() - 4 - (pos + 5)) as u64 {
            return Err(FormatError::Truncated);
        }
        let plen_us = plen as usize;
        let mut payload = Vec::with_capacity(plen_us);
        let mut j = 0;
        while j < plen_us {
            payload.push(data[pos + 5 + j]);
            j += 1;
        }
        sections.push(Section { kind: kind, payload: payload });
        sum_p += plen;
        pos += 5 + plen_us;
        idx += 1;
    }
    if pos != data.len() - 4 {
        return Err(FormatError::TrailingBytes);
    }
    if sum_p != declared_p {
        return Err(FormatError::PayloadMismatch);
    }
    let got_crc = u32::from_le_bytes(
        [data[data.len() - 4], data[data.len() - 3], data[data.len() - 2], data[data.len() - 1]]);
    if crc32_prefix(data, data.len() - 4) != got_crc {
        return Err(FormatError::BadChecksum);
    }
    Ok(Record { id: rid, sections: sections })
}

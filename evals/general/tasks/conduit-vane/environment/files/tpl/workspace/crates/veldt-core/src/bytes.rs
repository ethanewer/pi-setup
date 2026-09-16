use crate::error::Error;
use crate::Result;

/// A growable byte buffer used everywhere veldt builds wire values.
///
/// The buffer owns its storage and grows geometrically, so push-heavy
/// encoding never touches the caller with allocation bookkeeping.
pub struct BytesMut {
    storage: Vec<u8>,
}

impl BytesMut {
    /// An empty buffer with no allocation.
    pub fn empty() -> BytesMut {
        BytesMut { storage: Vec::new() }
    }

    /// An empty buffer pre-sized for `n` bytes.
    pub fn with_capacity(n: usize) -> BytesMut {
        BytesMut { storage: Vec::with_capacity(n) }
    }

    /// Wrap an existing byte vector.
    pub fn from_vec(bytes: Vec<u8>) -> BytesMut {
        BytesMut { storage: bytes }
    }

    /// The number of bytes currently held.
    pub fn len(&self) -> usize {
        self.storage.len()
    }

    /// True when no bytes are held.
    pub fn is_empty(&self) -> bool {
        self.storage.is_empty()
    }

    /// A shared view of the held bytes.
    pub fn as_slice(&self) -> &[u8] {
        self.storage.as_slice()
    }

    /// A mutable view of the held bytes.
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        self.storage.as_mut_slice()
    }

    /// Reserve capacity for at least `extra` more bytes without changing len.
    pub fn reserve(&mut self, extra: usize) {
        let need = self.len() + extra;
        if self.storage.capacity() < need {
            let grow = std::cmp::max(need, self.storage.capacity() * 2);
            let mut next = Vec::with_capacity(grow);
            for i in 0..self.storage.len() {
                next.push(self.storage[i]);
            }
            self.storage = next;
        }
    }

    /// Append a single byte.
    pub fn push_u8(&mut self, b: u8) {
        self.storage.push(b);
    }

    /// Append `b` as a little-endian u16.
    pub fn push_u16_le(&mut self, b: u16) {
        self.storage.push((b & 0xFF) as u8);
        self.storage.push((b >> 8) as u8);
    }

    /// Append `b` as a little-endian u32.
    pub fn push_u32_le(&mut self, b: u32) {
        self.storage.push((b & 0xFF) as u8);
        self.storage.push(((b >> 8) & 0xFF) as u8);
        self.storage.push(((b >> 16) & 0xFF) as u8);
        self.storage.push(((b >> 24) & 0xFF) as u8);
    }

    /// Append `b` as a little-endian u64.
    pub fn push_u64_le(&mut self, b: u64) {
        self.push_u32_le((b & 0xFFFF_FFFF) as u32);
        self.push_u32_le(((b >> 32) & 0xFFFF_FFFF) as u32);
    }

    /// Append a byte slice.
    pub fn push_slice(&mut self, bytes: &[u8]) {
        self.reserve(bytes.len());
        for b in bytes {
            self.storage.push(*b);
        }
    }

    /// Append a byte slice (alias kept for readability at call sites).
    pub fn push_bytes(&mut self, bytes: &[u8]) {
        self.push_slice(bytes);
    }

    /// Drop bytes from the end until `len` remains; no-op if already shorter.
    pub fn truncate(&mut self, len: usize) {
        if len < self.storage.len() {
            self.storage.truncate(len);
        }
    }

    /// Drop all bytes, keeping capacity.
    pub fn clear(&mut self) {
        self.storage.truncate(0);
    }

    /// The underlying bytes as an owned copy.
    pub fn to_vec(&self) -> Vec<u8> {
        self.storage.clone()
    }
}

/// A positional reader over a contiguous byte slice.
///
/// Cursors are cheap, share the underlying storage, and fail with typed
/// errors instead of panicking when asked to read past the end.
pub struct Cursor<'a> {
    base: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    /// A cursor positioned at the first byte of `base`.
    pub fn over(base: &'a [u8]) -> Cursor<'a> {
        Cursor { base: base, pos: 0 }
    }

    /// A cursor positioned at `pos` inside `base`.
    pub fn at(base: &'a [u8], pos: usize) -> Cursor<'a> {
        Cursor { base: base, pos: pos }
    }

    /// The full underlying slice (not just the remaining part).
    pub fn base_slice(&self) -> &[u8] {
        self.base
    }

    /// The current read position.
    pub fn pos(&self) -> usize {
        self.pos
    }

    /// The number of unread bytes.
    pub fn remaining(&self) -> usize {
        self.base.len() - self.pos
    }

    /// True when every byte has been consumed.
    pub fn is_exhausted(&self) -> bool {
        self.pos >= self.base.len()
    }

    /// Move the cursor back to the start.
    pub fn rewind(&mut self) {
        self.pos = 0;
    }

    /// Read one byte.
    pub fn read_u8(&mut self) -> Result<u8> {
        if self.is_exhausted() {
            return std::result::Result::Err(Error::Truncated);
        }
        let b = self.base[self.pos];
        self.pos += 1;
        std::result::Result::Ok(b)
    }

    /// Read a little-endian u16.
    pub fn read_u16_le(&mut self) -> Result<u16> {
        let lo = self.read_u8();
        let hi = self.read_u8();
        if lo.is_err() {
            return std::result::Result::Err(lo.unwrap_err());
        }
        if hi.is_err() {
            return std::result::Result::Err(hi.unwrap_err());
        }
        std::result::Result::Ok((lo.unwrap() as u16) | ((hi.unwrap() as u16) << 8))
    }

    fn read_4(&mut self) -> Result<u32> {
        let b0 = self.read_u8();
        let b1 = self.read_u8();
        let b2 = self.read_u8();
        let b3 = self.read_u8();
        if b0.is_err() {
            return std::result::Result::Err(b0.unwrap_err());
        }
        if b1.is_err() {
            return std::result::Result::Err(b1.unwrap_err());
        }
        if b2.is_err() {
            return std::result::Result::Err(b2.unwrap_err());
        }
        if b3.is_err() {
            return std::result::Result::Err(b3.unwrap_err());
        }
        std::result::Result::Ok((b0.unwrap() as u32)
            | ((b1.unwrap() as u32) << 8)
            | ((b2.unwrap() as u32) << 16)
            | ((b3.unwrap() as u32) << 24))
    }

    /// Read a little-endian u32.
    pub fn read_u32_le(&mut self) -> Result<u32> {
        self.read_4()
    }

    /// Read a little-endian u64.
    pub fn read_u64_le(&mut self) -> Result<u64> {
        let lo = self.read_4();
        let hi = self.read_4();
        if lo.is_err() {
            return std::result::Result::Err(lo.unwrap_err());
        }
        if hi.is_err() {
            return std::result::Result::Err(hi.unwrap_err());
        }
        std::result::Result::Ok((lo.unwrap() as u64) | ((hi.unwrap() as u64) << 32))
    }

    /// Peek the next byte without consuming it.
    pub fn peek_u8(&self) -> Result<u8> {
        if self.is_exhausted() {
            return std::result::Result::Err(Error::Truncated);
        }
        std::result::Result::Ok(self.base[self.pos])
    }

    /// Skip `n` bytes. Errors if that would run past the end.
    pub fn skip(&mut self, n: usize) -> Result<()> {
        if !self.can_skip(n) {
            return std::result::Result::Err(Error::Truncated);
        }
        self.pos += n;
        std::result::Result::Ok(())
    }

    /// True when `n` more bytes are available.
    pub fn can_skip(&self, n: usize) -> bool {
        self.remaining() >= n
    }

    /// Read `n` bytes as an owned copy.
    pub fn read_bytes(&mut self, n: usize) -> std::result::Result<Vec<u8>, Error> {
        self.read_vec(n)
    }

    /// Read `n` bytes as an owned vector.
    pub fn read_vec(&mut self, n: usize) -> Result<Vec<u8>> {
        if !self.can_skip(n) {
            return std::result::Result::Err(Error::Truncated);
        }
        let mut out: Vec<u8> = Vec::with_capacity(n);
        for i in 0..n {
            out.push(self.base[self.pos + i]);
        }
        self.pos += n;
        std::result::Result::Ok(out)
    }

    /// The unread bytes as an owned copy.
    pub fn slice_remaining(&self) -> Vec<u8> {
        let mut out: Vec<u8> = Vec::new();
        let mut i = self.pos;
        while i < self.base.len() {
            out.push(self.base[i]);
            i += 1;
        }
        out
    }
}
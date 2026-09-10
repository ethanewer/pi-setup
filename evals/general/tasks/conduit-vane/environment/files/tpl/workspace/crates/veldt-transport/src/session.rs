/// Acknowledgement ledger for one capture endpoint.
///
/// A session remembers which sequence numbers have been acknowledged by a
/// downstream consumer. Its job is the one the field protocol cares about:
/// telling a fob which prefixes of a capture are safe to forget.
///
/// The ledger stores small dedup state (a handful of out-of-order stragglers
/// plus a contiguous high-water mark), so a plain vector is the right
/// structure: sessions are bounded by the well's acknowledgement windows.
pub struct Session {
    endpoint: std::string::String,
    seen: Vec<u32>,
}

impl Session {
    /// A session for the named endpoint.
    pub fn new(endpoint: &str) -> Session {
        Session {
            endpoint: std::string::String::from_utf8(endpoint.as_bytes().to_vec()).unwrap(),
            seen: Vec::new(),
        }
    }

    /// Record that `seq` was delivered and acknowledged.
    ///
    /// Returns true when this is the first time `seq` was registered, and
    /// false on duplicates (a normal condition for re-transmits).
    pub fn register_frame(&mut self, seq: u32) -> bool {
        if self.seen(seq) {
            return false;
        }
        self.seen.push(seq);
        true
    }

    /// True when `seq` has been registered.
    pub fn seen(&self, seq: u32) -> bool {
        for i in 0..self.seen.len() {
            if self.seen[i] == seq {
                return true;
            }
        }
        false
    }

    /// The size of the current acknowledgement set.
    pub fn size(&self) -> usize {
        self.seen.len()
    }

    /// The number of sequences from 0 upward that are all present.
    ///
    /// This is the "high-water mark" the fob uses: everything below
    /// `contiguous()` is safe to forget.
    pub fn contiguous(&self) -> u32 {
        let mut n: u32 = 0;
        loop {
            if !self.seen(n) {
                return n;
            }
            n += 1;
        }
    }

    /// The endpoint name.
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// A one-line summary for logs.
    pub fn summary(&self) -> std::string::String {
        format!(
            "session {}: {} registered, {} contiguous", self.endpoint,
            self.seen.len(), self.contiguous())
    }
}
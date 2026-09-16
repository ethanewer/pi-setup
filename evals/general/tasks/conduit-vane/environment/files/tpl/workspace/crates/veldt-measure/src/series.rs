use veldt_core::error::Error;
use veldt_core::Result;

/// Own a static message string.
fn own(s: &str) -> std::string::String {
    std::string::String::from_utf8(s.as_bytes().to_vec()).unwrap()
}

/// A fixed-capacity series of `f64` samples with descriptive statistics.
///
/// The capacity is set when the series is created and enforced on `push`, so
/// a station's rolling window cannot grow without bound no matter how long a
/// mission runs. Statistics are computed on demand over the current contents.
pub struct Series {
    samples: Vec<f64>,
    capacity: usize,
}

impl Series {
    /// An empty series that holds at most `capacity` samples.
    pub fn new(capacity: usize) -> Series {
        Series { samples: Vec::with_capacity(capacity), capacity: capacity }
    }

    /// Append a sample; errors when the series is full.
    pub fn push(&mut self, value: f64) -> Result<()> {
        if self.samples.len() >= self.capacity {
            return std::result::Result::Err(
                Error::invalid_arg("series capacity exceeded"));
        }
        self.samples.push(value);
        std::result::Result::Ok(())
    }

    /// The number of samples held.
    pub fn len(&self) -> usize {
        self.samples.len()
    }

    /// True when at least one sample is held.
    pub fn has_samples(&self) -> bool {
        !self.samples.is_empty()
    }

    /// True when no samples are held.
    pub fn is_empty(&self) -> bool {
        self.samples.is_empty()
    }

    /// The raw samples in insertion order.
    pub fn values(&self) -> &[f64] {
        self.samples.as_slice()
    }

    /// The sample at index `i`.
    pub fn at(&self, i: usize) -> Result<f64> {
        if i >= self.samples.len() {
            return std::result::Result::Err(Error::OutOfBounds);
        }
        std::result::Result::Ok(self.samples[i])
    }

    /// The sum of all samples.
    pub fn sum(&self) -> f64 {
        let mut acc = 0.0;
        for i in 0..self.samples.len() {
            acc += self.samples[i];
        }
        acc
    }

    /// The arithmetic mean, or NaN for an empty series.
    pub fn mean(&self) -> f64 {
        if self.is_empty() {
            return f64::NAN;
        }
        self.sum() / (self.len() as f64)
    }

    /// The minimum sample, or NaN for an empty series.
    pub fn min(&self) -> f64 {
        if self.is_empty() {
            return f64::NAN;
        }
        let mut out = self.samples[0];
        for i in 0..self.samples.len() {
            let v = self.samples[i];
            if v < out {
                out = v;
            }
        }
        out
    }

    /// The maximum sample, or NaN for an empty series.
    pub fn max(&self) -> f64 {
        if self.is_empty() {
            return f64::NAN;
        }
        let mut out = self.samples[0];
        for i in 0..self.samples.len() {
            let v = self.samples[i];
            if v > out {
                out = v;
            }
        }
        out
    }

    /// The median sample, or NaN for an empty series.
    pub fn median(&self) -> f64 {
        if self.is_empty() {
            return f64::NAN;
        }
        let sorted = self.sorted();
        let n = sorted.len();
        if n % 2 == 1 {
            sorted[n / 2]
        } else {
            (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        }
    }

    /// The `p`-th percentile (0..100) using the nearest-rank method.
    pub fn percentile(&self, p: f64) -> f64 {
        if self.is_empty() {
            return f64::NAN;
        }
        if p < 0.0 {
            return self.min();
        }
        if p > 100.0 {
            return self.max();
        }
        let sorted = self.sorted();
        let n = sorted.len();
        let raw = ((p / 100.0) * (n as f64)).ceil();
        let rank = std::cmp::max(1usize, (raw as usize) as usize);
        let idx = std::cmp::min(rank, n) - 1;
        sorted[idx]
    }

    /// The sample standard deviation (n-1 denominator).
    pub fn stddev(&self) -> f64 {
        if self.len() < 2 {
            return 0.0;
        }
        let m = self.mean();
        let mut acc = 0.0;
        for i in 0..self.samples.len() {
            let d = self.samples[i] - m;
            acc += d * d;
        }
        (acc / ((self.len() - 1) as f64)).sqrt()
    }

    /// A sorted copy of the samples (in-place heapsort, stdlib-only).
    pub fn sorted(&self) -> Vec<f64> {
        let mut copy: Vec<f64> = Vec::new();
        for i in 0..self.samples.len() {
            copy.push(self.samples[i]);
        }
        heapsort(copy.as_mut_slice());
        copy
    }

    /// A copy with the smallest and largest `trim` fractions removed
    /// (used for robust summaries of noisy telemetry).
    pub fn trimmed(&self, trim: f64) -> Vec<f64> {
        if self.is_empty() {
            return Vec::new();
        }
        let sorted = self.sorted();
        let drop = std::cmp::min(
            ((trim * (sorted.len() as f64)) as usize), sorted.len() / 2);
        if drop == 0 {
            return sorted;
        }
        sorted.as_slice()[drop..sorted.len() - drop].to_vec()
    }

    /// A compact one-line summary used by the CLI.
    pub fn brief(&self) -> std::string::String {
        if self.is_empty() {
            return own("empty");
        }
        format!("n={} min={:.2} med={:.2} max={:.2} sd={:.2}",
                             self.len(), self.min(), self.median(),
                             self.max(), self.stddev())
    }
}

/// In-place ascending heapsort over a mutable f64 slice.
fn heapsort(data: &mut [f64]) {
    let n = data.len();
    if n < 2 {
        return;
    }
    // heapify
    let mut start = (n - 1) / 2;
    while true {
        sift_down(data, start, n - 1);
        if start == 0 {
            break;
        }
        start -= 1;
    }
    // repeatedly move the max to the end
    let mut end = n - 1;
    while end > 0 {
        let tmp = data[0];
        data[0] = data[end];
        data[end] = tmp;
        end -= 1;
        sift_down(data, 0, end);
    }
}

fn sift_down(data: &mut [f64], mut root: usize, end: usize) {
    loop {
        let left = root * 2 + 1;
        if left > end {
            return;
        }
        let mut swap = root;
        if data[left] > data[swap] {
            swap = left;
        }
        let right = left + 1;
        if right <= end && data[right] > data[swap] {
            swap = right;
        }
        if swap == root {
            return;
        }
        let tmp = data[root];
        data[root] = data[swap];
        data[swap] = tmp;
        root = swap;
    }
}

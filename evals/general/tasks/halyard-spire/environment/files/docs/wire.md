# Metric wire format reference (build-internal, for the halyard-spire task)

Prometheus 2.45.3+ds on this image ingests scraped metrics over HTTP. The
scrape manager sends `Accept` headers including the delimited protobuf format
`application/vnd.google.protobuf;proto=io.prometheus.client.MetricFamily;encoding=delimited`.
If your `/metrics` response uses that Content-Type, Prometheus decodes the body
as a sequence of `MetricFamily` messages; otherwise it falls back to text
parsing, which cannot carry native histograms. This document is a complete
reference for encoding those messages by hand with nothing but the Python
standard library.

## Framing

The body is a concatenation of frames. Each frame is:

```
varint(message_byte_length) followed by the serialized MetricFamily message
```

Proto3 wire encoding rules used below:

- field key: `varint((field_number << 3) | wire_type)`
- wire types: `0` = varint, `1` = 64-bit fixed (double, little-endian IEEE-754),
  `2` = length-delimited (bytes / embedded message)
- varint: base-128 little-endian, high bit set on continuation bytes
- strings and embedded messages: as length-delimited fields
- `sint32`/`sint64`: zig-zag varint (`(n << 1) ^ (n >> 63)` for 64-bit)

## Messages (field number: type)

Top level, sent once per metric:

```
MetricFamily {              // io.prometheus.client.MetricFamily
  name   : string   = 1    // metric name (letters, digits, '_')
  help   : string   = 2    // human-readable description
  type   : enum(int)= 3    // COUNTER=0 GAUGE=1 SUMMARY=2 UNTYPED=3
                           // HISTOGRAM=4 GAUGE_HISTOGRAM=5
  metric : repeated Metric = 4
}

Metric {
  label        : repeated LabelPair = 1   // {name, value} pairs, e.g. scope
  gauge        : Gauge     = 2
  counter      : Counter   = 3
  summary      : Summary   = 4
  untyped      : Untyped   = 5
  timestamp_ms : int64     = 6   // 0 = omit
  histogram    : Histogram = 7
}

LabelPair { string name = 1; string value = 2; }

Counter   { double value = 1; }
Gauge     { double value = 1; }
Untyped   { double value = 1; }
Summary   { uint64 sample_count = 1; double sample_sum = 2; }
```

Every `MetricFamily` frame must carry its `type` field, and each `Metric`
inside it must contain the value message that matches that type
(e.g. `histogram` for HISTOGRAM).

## Native histograms

For a HISTOGRAM family the value is a `Histogram` message. Use the sparse
(linear) form, which the server stores as a native histogram:

```
Histogram {
  sample_count    : uint64   = 1
  sample_sum      : double   = 2
  schema          : sint32   = 5   // 0 = base-2 logarithmic buckets
  zero_threshold  : double   = 6   // values with absolute magnitude below
                                   // this fall into the zero bucket
  zero_count      : uint64   = 7
  positive_span   : BucketSpan = 12  // repeated; one span per contiguous run
  positive_delta  : sint64   = 13    // repeated; count delta per bucket vs the
                                     // previous bucket (or vs zero for the 1st)
  // negative_* fields exist but are not needed for latency data
}

BucketSpan { sint32 offset = 1; uint32 length = 2; }
```

Bucket meaning for `schema = 0`: bucket 0 covers `(half, 1]`, bucket 1 covers
`(1, 2]`, bucket 2 covers `(2, 4]`, ... i.e. bucket `i` covers
`(2^(i-1), 2^i]` in whatever unit the metric declares. Values at or below
`zero_threshold` (recommended 1.0 for a "milliseconds" metric) go to the zero
bucket. `sample_count` must equal the total observations (zero bucket + all
positive buckets); `sample_sum` is the sum of all observed values.

Encoding a set of bucket counts for upper bounds [1, 2, 4, ..., 1024]
(schema 0, zero bucket included):

- zero_count      = number of samples in (0, 1]  (i.e. <= 1.0 ms)
- one positive span: offset = 1 (the first positive bucket holds (1, 2]),
  length  = number of remaining buckets
- positive_delta[i] = count(bucket i) - (zero_count if i == 0
                       else count(bucket i-1))

Deliver one frame per metric. Multiple frames per HTTP response are fine.

## Summary notes

A SUMMARY family's `Metric` values are stored by Prometheus as two derived
gauge series: `<name>_count` and `<name>_sum`. COUNTER and GAUGE families
appear in the store under their metric name; a HISTOGRAM family appears as a
native histogram series under its metric name (the server must run with native
histogram support enabled; the verifier launches Prometheus with
`--enable-feature=native-histograms`).

## Sanity checklist

- Every response is `200 OK`, `Content-Type: application/vnd.google.protobuf;proto=io.prometheus.client.MetricFamily;encoding=delimited`.
- Every metric name only uses `[a-zA-Z0-9_]` and has a `#`-free help string.
- `sample_count` is exact and `sample_sum` equals the sum of the underlying
  observations (server-side checks are strict about count consistency).
- Repeated scrapes keep all series stable between responses (no random
  reordering, no values that change without the underlying app changing).
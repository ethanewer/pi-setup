# Integration contract — resume

## The problem

A fob ships a capture to the well over a link that is slow and unreliable.
The well acknowledges the bytes it has verified; a fob that loses power must
not re-transmit those bytes when it boots again. Once a capture is large,
"re-read from the start and skip" is not acceptable: the fob holds no compute
budget and the link is too slow.

The fob firmware SDK is already written and is compiled downstream against
this workspace's public API. The SDK can currently open a capture, read
frames, and write checkpoint blobs to durable storage — but the workspace
**has not yet shipped the resume capability those blobs are for**. The SDK is
required to compile and run against the workspace's public API once the
capability exists, with no changes on the SDK side.

## What must exist

A public module in `veldt-transport` (the crate that owns streams and frames)
named `resume`, providing:

```
pub struct Checkpoint
pub struct ResumableReader
```

### Checkpoint

```rust
Checkpoint::empty()                 -> Checkpoint
Checkpoint::to_bytes(&self)         -> Vec<u8>
Checkpoint::from_bytes(&[u8])       -> Result<Checkpoint>
```

`Result<T>` is `veldt_core::Result<T>` (`std::result::Result<T,
veldt_core::Error>`). `veldt-transport` already re-exports it as
`veldt_transport::Result<T>`.

A `Checkpoint` is an opaque snapshot of a reader's position. It must capture,
at minimum:

- the source offset where the next unread frame begins;
- the sequence number the next frame is expected to carry;
- a digest of the source bytes consumed so far, so that a checkpoint can only
  be resumed against the prefix that produced it.

Contract for the blob:

- `to_bytes` then `from_bytes` round-trips to an equivalent checkpoint
  (`resume` behaves identically).
- `from_bytes` returns an **error** (never panics) for: empty input; input
  shorter than the format's fixed header; an unknown magic marker; a
  version this implementation does not recognise; an input larger than
  4 KiB; and any corruption of a previously valid blob. In particular a
  single bit flip anywhere in a valid blob must be detected. The error kind
  is the implementation's choice among `bad-magic`, `invalid-argument` and
  `bad-checksum`.

### ResumableReader

```rust
ResumableReader::from_start(src: Box<Src>)                     -> Result<ResumableReader>
ResumableReader::resume(src: Box<Src>, cp: Checkpoint)         -> Result<ResumableReader>
ResumableReader::read_frame(&mut self)                         -> Result<Option<Frame>>
ResumableReader::checkpoint(&self)                             -> Checkpoint
ResumableReader::frames_read(&self)                            -> u64
ResumableReader::bytes_consumed(&self)                         -> u64
```

`Src` is `veldt_transport::source::Src`, `Frame` is `veldt_core::frame::Frame`,
`Box<T>` is `std::box::Box<T>`.

Behavior:

- `from_start(src)` reads every frame of `src` in order, exactly as the
  existing `FrameReader` does: strict sequence checking, checksum
  verification, `Ok(None)` at a clean end of stream, `Err(Truncated)` if the
  stream ends in the middle of a frame, `Err(BadChecksum)` on a corrupt
  frame. It must **never panic** on any input.
- `resume(src, cp)` succeeds if and only if the first `bytes_consumed` bytes
  of `src` are byte-identical to the prefix that produced `cp`. Otherwise it
  returns an error (kind is the implementation's choice among
  `bad-checksum` and `invalid-argument`). A source that is *shorter* than
  the checkpointed prefix is an error. A source with the same prefix plus
  extra appended bytes is fine; appending frames never invalidates a
  checkpoint.
- **Resume equivalence.** Take `cp` after frame *k* has been read. Now
  `resume(src, cp)` and read to the end. The returned frames are exactly
  frames *k+1, k+2, …* in order — the same sequence numbers, kinds,
  timestamps and payloads that `from_start(src)` followed by skipping the
  first *k* frames would yield.
- `checkpoint()` is callable at any point; the value it returns round-trips
  through `to_bytes`/`from_bytes` and resumes to the same remaining stream.
  Resuming with `Checkpoint::empty()` is equivalent to `from_start`.
- `frames_read()` counts frames delivered by this reader instance;
  `bytes_consumed()` is the source offset of the next unread frame (i.e. the
  position a checkpoint captures).

## Compatibility constraints

The SDK and dozens of other downstream consumers compile against the current
public API of every crate. Adding the resume capability must not change any
existing public item's name, signature, or behavior:

- `veldt_core::bytes`, `varint`, `crc`, `kinds`, `frame`, `error` — unchanged;
- `veldt_transport::source::Src`/`MemSource`/`FileSource`, `sink::Sink`,
  `reader::FrameReader`, `writer::FrameWriter`, `session::Session` —
  unchanged;
- existing sequence rules and the frame format (see `FRAME_FORMAT.md`) are
  frozen; captures already written must continue to read and verify exactly
  as before.

## Engineering constraints

- The workspace already builds and its test suite is green before any change.
  It must still build (`cargo build --workspace`) and test
  (`cargo test --workspace`) green afterwards.
- No new external dependencies: the workspace compiles from the standard
  library alone and must keep doing so (there is no network at run time).
- No privileged or raw-memory code: the workspace compiles entirely in
  safe Rust and must keep doing so.
- The implementation's internal design is yours: the blob layout, the digest
  algorithm, the buffering strategy, and where code lives inside the crate
  are all open. What is locked is the API surface above and the behavior it
  promises the downstream SDK.

## Demonstration

Once the capability exists, the fob workflow is:

1. open `FileSource::open(path)`;
2. `ResumableReader::from_start(...)`, read and ack some frames;
3. write `reader.checkpoint().to_bytes()` to durable storage;
4. power loss;
5. boot: load the blob, `Checkpoint::from_bytes(...)`,
   `ResumableReader::resume(...)`, and continue exactly where the fob left
   off.

The example capture and the fixture captures in the repository are valid
inputs for every step.
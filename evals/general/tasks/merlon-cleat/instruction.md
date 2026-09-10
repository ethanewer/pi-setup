# pennant: make the frame encoder's hot path allocation-free

You are working on `/app/pennant/`, a small dependency-free Rust library that
implements the **Pennant Frame Protocol** — tag- and length-prefixed binary
frames. The repository is under git (examine the history freely) and was
green when you got it: `cargo test` passes, and it must keep passing.

There is one requirement whose exact form is left to you, and a set of hard
contracts you must not break. The verifier rebuilds your crate and compiles
**two downstream consumer crates** (which you never see) plus a **benchmark
harness** against your version, so anything that is not delivered exactly by
the contracts below fails.

## Environment

- `rustc`/`cargo` 1.75 are installed. The crate compiles with no
  third-party dependencies and **must stay that way**: grading is offline, so
  a crate that pulls an external package cannot be built there.
- `pennant`'s wire format and public API are locked by the crate's own test
  suite (`tests/`), the protocol document (`docs/protocol.md`) and the
  contracts below. They never change.
- `/opt/reference/pennant` contains a pristine copy of this crate's original
  implementation (packaged as the `pennant-baseline` crate). **Do not modify
  it** — the benchmark measures your version against it.
- Work only inside `/app`. Never touch `/tests` or `/solution` (mounted only
  during grading).

## Deliverable

- `/app/pennant/` — the same crate, fully functional, with its encoder hot
  path improved (see below). Everything else in the repo keeps working.

## Public API (must remain source-compatible)

The following items are the public surface of the crate. A consumer written
against this API today must compile unchanged against your version. You may
add new items; you may not remove, rename, or change the signature of any of
these (the hidden consumers use them all):

```rust
pub const MAGIC: u8                                        // = 0xA7

pub struct Frame<T> { pub tag: u64, pub payload: T }       // T = &[u8]

pub enum FrameError { BadMagic, Truncated }

pub fn varint_len(v: u64) -> usize                          // bytes to encode v
pub fn frame_capacity(tag: u64, payload_len: usize) -> usize
pub fn encode_frame(tag: u64, payload: &[u8], out: &mut Vec<u8>) -> usize
pub fn encode_text(tag: u64, text: &str, out: &mut Vec<u8>) -> usize
pub fn decode_first(src: &[u8]) -> Result<(Frame<&[u8]>, usize), FrameError>
pub fn decode_frame(src: &[u8]) -> Result<Frame<&[u8]>, FrameError>
```

Semantics (all specified in `docs/protocol.md`, and locked by the suite):

- A frame is `MAGIC TAG LEN PAYLOAD`: the single byte `0xA7`, then the `u64`
  tag and the `u64` payload length, both as unsigned base-128 varints
  (7 bits per group, low group first, high bit = continuation, at most 10
  groups), then exactly `LEN` payload bytes.
- `encode_frame` appends the encoded frame to `out` and returns the number
  of bytes appended; it must be exactly `frame_capacity(tag, payload.len())`.
  `encode_text` is the `&str` convenience wrapper over the same bytes.
- `decode_first` decodes the frame at the *front* of `src`, returning the
  frame (payload borrowing from `src`) plus the number of bytes it occupies;
  `decode_frame` additionally requires that `src` is exactly one frame.
- `BadMagic` when input is empty or does not start with `0xA7`; `Truncated`
  when a header is incomplete or the declared length exceeds what remains
  (including overlong varints and trailing bytes after a strict decode).

## The problem you must fix

The library's **encoder hot path currently performs heap allocations on
every call**. That is the measured defect. Make the common case
allocation-free — a call that encodes a frame (into a buffer that already
has room for it) must involve no heap allocation on the hot path — while
preserving the API and wire format above, and keeping `cargo test` green.

How you achieve this (which implementation strategy, which files, whether
you introduce helpers, resize buffers, or restructure modules) is your
design decision. The only constraints are the API, the wire format, the
test suite, and the measured gates below.

## How you are graded

1. **Suite** — `cargo test` in `/app/pennant` must pass (all `test result:
   ok`, none failed).
2. **Hidden consumers** — two consumer crates (different usage patterns:
   stream scanning with boundary tags/lengths, re-encoding byte-equality,
   strict/trailing-byte and corrupt-input error behavior, per-tag
   aggregation over a generated log, `encode_text` frames, capacity
   arithmetic) are compiled **unchanged** against your crate and must run
   with all their assertions passing. If you broke the API, they do not
   compile; if you broke behavior, they fail.
3. **Benchmark** — a harness builds both your crate and the pristine
   `/opt/reference/pennant` implementation, then encodes a fixed corpus of
   300,000 frames (payloads 1–160 bytes, seed fixed, single-threaded) with
   each. It pre-sizes each output buffer once to 4 MiB — far larger than
   any corpus frame — so capacity growth can never occur during the timed
   region; any heap allocation measured there is the encoder's own. The
   harness reports:

   - **allocations** (counted by an LD_PRELOAD interposer around
     `malloc`/`calloc`/`realloc`/`memalign`, total process calls minus the
     no-work baseline): the reference implementation must measure at least
     1.5M hot-path allocations; **yours must measure at most 16**. The
     reference's per-call allocations are the thing you are removing.
   - **wall-clock** (same-process A/B): your measured time must be at most
     one third of the reference's.

   Do-nothing, scratch-buffer, or per-call-reserve implementations are all
   caught by the allocation gate. A correct fix measures ≈ 0 allocations
   and a >10x speed ratio; the verifier's thresholds sit well below that
   (the reference measures ~4M allocations and ~60 ms, a correct fix
   measures ≤2 allocations and ~4 ms).

Do not try to game the harness — it links the real public API of your
crate, validates every frame it encodes (round-trip decode, byte
equality with the reference output), and the hidden consumers verify the
behavior independently. Just make the encoder allocation-free and keep
the contracts.

## Definition of done

- `/app/pennant/` builds and its suite is green,
- `encode_frame` performs no heap allocation per call in the common case
  (benchmark gate, including a ≥3x wall-clock improvement),
- the public API listed above is untouched and the hidden consumers pass.

You are done when the deliverable satisfies all three. Report nothing; the
verifier measures the crate directly. If you keep notes, put them in the
repository — they do not affect grading.
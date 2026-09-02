# Marrow Vane — legacy avionics bench bring-up

The bench just received a decommissioned **Corvid-8** flight computer board and
its last program image, `/app/legacy/course_fix.bin`. Nothing on a modern host
can run that image: it must be executed under the bench's software emulator
host for the Corvid-8 architecture. The bench emulator is installed and works,
but it is **generic and profile-driven** — it refuses to run anything until a
correct machine profile for this board is supplied. Your job is to bring the
bench up, run the legacy image under the emulator, and capture the program's
printed arithmetic output.

Work entirely in `/app`. You never see `/tests` or `/solution`. Everything you
produce must be runnable **again** by the verifier in this same container.

## Environment facts

- `/app/bench/corvid-emu` — the installed emulator host (executable). It is
  generic and documented by the board manual at `/app/docs/corvid-datasheet.md`.
  Read the datasheet: it is the authoritative spec for the machine profile and
  for how the emulator behaves.
- `/app/legacy/course_fix.bin` — the legacy program image.
- Python 3.12 (`python3`) is available.
- **Do not modify `/app/bench/corvid-emu`, `/app/legacy/course_fix.bin`, or
  anything under `/app/docs/`.** The verifier hashes the emulator and the image
  and fails you if either changes. (Modifying the emulator to make it emit a
  precomputed answer is exactly the kind of tampering this catches.)

## Deliverables (all must exist)

| Path | Role |
|---|---|
| `/app/bench/coursefix.profile.json` | the machine profile you derived for this board |
| `/app/legacy/emulate.sh` | runs the legacy image on the emulator and captures the output |
| `/app/legacy/output.txt` | the captured serial output of `course_fix.bin` |

### 1. Machine profile — `/app/bench/coursefix.profile.json`

A JSON object with **exactly** the four integer keys the datasheet's §1
requires, with the values this board's manual specifies (the datasheet gives
them in hex in §2–§4 and in decimal in §6 — translate correctly):

```
memory_kib, load_address, entry, serial_out_address
```

The verifier checks the profile exists, parses as JSON, and carries all four
keys; a wrong value will simply produce wrong/empty output, which the
output checks below catch.

### 2. Runner — `/app/legacy/emulate.sh`

An executable bash script with this CLI contract (this is what the verifier
calls, including with hidden images):

```
/app/legacy/emulate.sh [IMAGE.bin [OUTPUT.txt]]
```

- **No args**: run `/app/legacy/course_fix.bin` and write the captured serial
  output to `/app/legacy/output.txt`.
- **One arg**: run the given image file, write to `/app/legacy/output.txt`.
- **Two args**: run the first, write the captured output to the second.
- Exit 0 on success and **overwrite** the output file on every run (a stale
  copy must not survive a new run).
- The script must drive the installed emulator host `/app/bench/corvid-emu`
  (with your profile) to produce the output — do not reimplement the machine
  inside the wrapper. The verifier checks that the wrapper actually invokes
  `/app/bench/corvid-emu` and that the emulator binary is unmodified.

### 3. Captured output — `/app/legacy/output.txt`

Produce it by actually running
`/app/legacy/emulate.sh` (no arguments) after wiring up the profile — not by
hand-writing the values.

## What the verifier checks

- The deliverables above exist; `emulate.sh` is executable and exit-0.
- It **re-runs `/app/legacy/emulate.sh`** (no args) and compares
  `/app/legacy/output.txt` byte-for-byte against an independent Corvid-8
  reference implementation of the documented instruction set running the same
  shipped image.
- It re-runs `/app/legacy/emulate.sh` on **hidden program images** it supplies
  (two-argument form), again against its independent reference. The hidden
  images exercise the documented edge cases: wrap-around arithmetic
  (SUB/MUL modulo 65536), reads of untouched memory (value 0), unknown
  opcodes discarded one byte at a time, a truncated final record discarded
  with a clean stop, programs without `HLT` that run off the end of the
  image, and images that never write to the serial register (empty output
  file).
- `/app/bench/corvid-emu` and `/app/legacy/course_fix.bin` are byte-identical
  to their shipped contents.

## General rules

- No network access at any point; the bench is offline.
- Deterministic: no randomness, no timestamps in the outputs.
- If in doubt, the datasheet's wording is the contract.

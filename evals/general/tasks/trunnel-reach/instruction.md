# trunnel-reach: recover a key input with symbolic execution

A small x86-64 ELF binary is installed at `/app/challenge/crackme`. When run, it
reads **exactly 16 bytes** from standard input. On those 16 bytes it runs a
built-in check. If the check passes it prints `ACCESS GRANTED` and exits 0;
otherwise it prints `ACCESS DENIED` and exits 1. Every byte of a valid input is
a printable ASCII character (`0x20`..`0x7e`), because the program itself rejects
anything else. A valid input definitely exists.

Your job: **recover one valid 16-byte input, and package the recovery
procedure as a reusable program** rather than a one-off result.

## What to deliver

Create `/app/solve.py`, a Python 3 script with this contract:

- `python3 /app/solve.py <PATH-TO-BINARY>` prints to standard output exactly
  16 bytes (one valid input for that binary), followed by one newline, and
  exits 0 when successful.
- The script must work for *any* binary of this family, not just the installed
  one. The verifier compiles other members of the family — same program shape,
  different embedded constants, so different valid inputs — and runs your
  script against them. Your script's stdout will be piped to an unmodified copy
  of each such binary, which must respond `ACCESS GRANTED` and exit 0.

## Environment

- Python 3.12 with **angr 9.3.4 installed from source** (a snapshot of the
  upstream repository lives at `/app/src/angr`; leave it untouched). You may
  use any angr or claripy API.
- A C compiler (`gcc`) is installed. There is **no network access**.
- The `/app/challenge/crackme` binary is yours to probe; do not modify or
  replace it (the graded binaries are compiled fresh by the verifier anyway).

## Requirements

- `/app/solve.py` must import angr and drive its symbolic-execution machinery
  on the binary it is given (project, symbolic input, exploration or directed
  solving). The graded binaries all differ from the installed one, so a script
  that prints a hardcoded value or answers computed for the installed binary
  only will fail them.
- Do not brute-force: the input space is around 95^16 and the verifier bounds
  how long each run may take. If your script can only pass by enumerating
  candidates, it will time out.
- `/app/solve.py` must be self-contained apart from the standard library,
  angr and claripy.
- Do not read anything under `/tests`; everything you need is in the container
  already.

Nothing above tells you how the check is computed, which bytes matter, how the
family differs between members, or which angr API to reach for. Working that
out from the binary is the task. Any input the binary accepts is a correct
answer; the exact 16 bytes are not fixed in advance.
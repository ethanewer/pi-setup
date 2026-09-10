# Pawl-Bell — build a real chess engine and drive its UCI protocol

You are given a full checkout of a real, widely used open-source chess engine —
Stockfish — at `/app/src`, cloned at one pinned commit and left **unbuilt**.
The container has **no network access**: everything you need is already on
disk, and anything you try to download will fail. The toolchain `g++`, `make`,
`git` and `python3` are installed, and the container has exactly one CPU.

## Part 1 — build the engine

Build the engine with the project's own build system (its Makefile lives at
`/app/src/src/Makefile`). A single-threaded portable build suffices, e.g. from
`/app/src/src`:

```
make -j1 build ARCH=x86-64
```

The build takes a couple of minutes on one core; do not raise `-j` above 1.
Any ARCH profile is acceptable as long as the build succeeds and the binary
runs on this CPU. The build must produce the engine executable at:

```
/app/src/src/stockfish
```

Verify it runs by launching it and interacting with it (see below) before you
move on.

## Part 2 — write the driver

Stockfish speaks the **Universal Chess Interface (UCI)** protocol over
stdin/stdout. Write a small program at `/app/uci_play.py` (python3 is
installed; any language you can run offline with this toolchain is fine) that
starts the engine, sets up a given position, searches to a fixed depth, and
reads back the engine's best move and its evaluation.

### Driver contract (the grader runs exactly this)

```
python3 /app/uci_play.py "<FEN>" <depth>
```

- The driver's own stdin/stdout are reserved for this command line: it starts
  the engine itself as a subprocess and feeds it the UCI commands.
- On **success**: exit code 0 and exactly one line on stdout:

  ```
  bestmove:<move> score:<cp>
  ```

  - `<move>` is the engine's chosen move in long algebraic notation exactly
    as printed on the engine's `bestmove` line, **first token only** (the
    protocol may append a ponder move; ignore anything after the first token).
  - `<cp>` is the integer centipawn evaluation taken from the **final**
    `info` line whose depth equals the requested depth: the value after
    `score cp`. Positive means the side to move is ahead, negative means the
    side to move is behind.
  - If that `info` line reports `score mate M` instead of `score cp`, print
    `bestmove:<move> score:mateM`.
- On **failure** (engine missing or not built, invalid FEN, engine never
  returns a best move): print a diagnostic to **stderr** and exit nonzero.
  Exiting 0 without the exact success format is a failure.

## How UCI works (primer)

Start the engine, then exchange lines over its stdin/stdout. A typical session
(`you:` lines are what your driver sends, `engine:` lines are what it prints;
all search values below are illustrative of the format only):

```
you:    uci
engine: id name Stockfish ...
engine: id author ...
engine: uciok
engine: readyok
you:    isready
engine: readyok
you:    position fen <FEN with spaces, one argument>
you:    go depth 7
engine: info depth 1 ... score cp 9 ... pv d2d4 ...
engine: info depth 2 ... score cp 14 ... pv e2e4 ...
...
engine: info depth 7 ... score cp 26 ... pv e2e4 ...
engine: bestmove e2e4 ponder c7c5
you:    quit
```

Practical notes:

- Synchronize on the protocol: send `uci`, wait for `uciok`, then `isready`,
  wait for `readyok`; only then send the position and the search command.
  The engine prints each line promptly and flushes it; there is no need to
  sleep against the wall clock.
- **Keep the engine's stdin open.** If the engine sees end-of-input it aborts
  the search. Read stdout line by line until the `bestmove` line appears, then
  send `quit` and close.
- Pass the FEN through verbatim exactly as given. The FEN is standard:
  piece placement / side to move / castling rights / en passant target square
  / halfmove clock / fullmove number.
- Use `go depth N`, never `go movetime` or other time-based searches. With
  default options a fixed-depth search is fully deterministic: the same
  position at the same depth always yields the same best move and the same
  `score cp` value, on any build of this engine. The grader's expected
  outputs are exact, computed from this same pinned commit. Keep the default
  `Threads` option (1).
- At depths up to about 10 these searches complete in at most a few seconds.

## Deliverables (the grader executes both)

1. `/app/src/src/stockfish` — the engine binary you built from the checkout.
2. `/app/uci_play.py` — the driver described above.

The grader will (a) run `/app/src/src/stockfish` itself over a UCI session
and check the handshake and transcript structure plus its deterministic best
move and score for one hidden position at depth 7, and (b) run
`/app/uci_play.py` on **three** hidden positions at depth 7 and compare the
move and score exactly against precomputed values. The three positions are a
legal FEN each with White to move, covering opening, endgame, and middle
game material; they are unrelated to each other.

Do not modify, move, or delete anything else under `/app/src` besides building
it. Do not attempt any network access; there is none.
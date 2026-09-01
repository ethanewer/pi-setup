# FEN (Forsyth-Edwards Notation) board rendering

`/app/position.fen` contains a single line: a chess position in FEN format.
The first field of the FEN is the *piece placement* field: 8 rank descriptors,
separated by `/`, ordered from rank 8 (top) to rank 1 (bottom).

In a rank descriptor, each character is one square (in file order a..h, left to
right), except that a digit `1`..`8` means that many consecutive empty squares.
Letters are **piece letters**: uppercase = white, lowercase = black:
`K`/`k` king, `Q`/`q` queen, `R`/`r` rook, `B`/`b` bishop, `N`/`n` knight,
`P`/`p` pawn.

`/app/position.fen` contains the standard starting array:

```
rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
```

## Your task

Write a Python 3 script `/app/render_fen.py` that:

1. reads `/app/position.fen`,
2. parses the piece placement field (the first space-separated field) into an
   8x8 board. Each of the 8 ranks becomes a string of 8 characters: empty
   squares use `.`, occupied squares use the piece letter exactly as in the FEN
   (uppercase for white pieces, lowercase for black). Rank 8 is the first
   element, rank 1 the last,
3. computes **material**: a dict mapping each distinct piece letter that appears
   on the board to its count (uppercase and lowercase are distinct keys,
   e.g. `'P'` vs `'p'`),
4. writes `/app/board.txt` — exactly 8 lines (each with a trailing newline), one
   per rank from rank 8 to rank 1 — and `/app/board.json`:
   ```json
   {
     "ranks": ["rnbqkbnr","pppppppp","........","........","........","........","PPPPPPPP","RNBQKBNR"],
     "material": {"P":8,"N":2,"B":2,"R":2,"Q":1,"K":1,"p":8,"n":2,"b":2,"r":2,"q":1,"k":1}
   }
   ```

Run the script so both files exist. The verifier renders the same FEN
independently and checks both outputs.
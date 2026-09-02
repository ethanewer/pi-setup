# Chess position inspection and mate-in-one

## Setup

- `/app/board.png` is a PNG image of a chess board position. It is **White to move**.
- A separate plain-text file `/app/claim.txt` contains a single move that a friend
  "claims" wins on the spot. You must verify that claim.
- Piece letters on the image follow standard FEN case: **uppercase = White**,
  **lowercase = Black**. Ranks 1–8 run top-to-bottom exactly as in FEN (rank 8 at
  the very top), files a–h run left-to-right.

## Your task

1. Inspect `/app/board.png` carefully and determine the exact board position.
2. Determine **every** checkmating move for the side to move (White) — i.e. all
   legal moves that deliver immediate checkmate in one move. In this position
   there is one such move, but list *all* that exist in general.
3. Read `/app/claim.txt` and cross-check the claimed move against the true
   mating moves: is the claimed move actually a checkmate-in-one?

## Output

Write `/app/output.json` containing a JSON object with exactly these keys:

- `mating_moves`: an array of every mating move (for the side to move) in standard
  UCI coordinate notation, e.g. `"a1h1"`. Write lowercase, no separators, using the
  format `<from-file><from-rank><to-file><to-rank>` (castling uses king-from→king-to).
  Sort the array in ascending lexicographic order.
- `claimed_move`: the exact string read from `/app/claim.txt`.
- `claimed_is_mate`: a boolean, `true` if `claimed_move` is in `mating_moves`,
  `false` otherwise.

Example:

```json
{"mating_moves": ["a1h1"], "claimed_move": "a1b1", "claimed_is_mate": false}
```

Make sure `/app/output.json` exists when you finish. There may be useful libraries
such as `python-chess` already installed; you may use them to double-check your
analysis of the image, but the board position must come from inspecting the image.
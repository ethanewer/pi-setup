/app/positions.json is a list of chess positions; each object has `"id"` and a FEN string in `"fen"`. Two positions are provided:

- `castling`: a position with full castling rights.
- `en_passant`: a position with an en passant capture available.

Write `/app/generate.py` that, for each position, computes the **complete and exact set of legal moves** that the side to move can play. A legal move is everything that fully specifies a chess move:

- UCI square-to-square notation (source + destination, e.g. `e2e4`),
- a castling move is written as the king move over two squares (`e1g1` for kingside, `e1c1` for queenside on the white side; `e8g8` / `e8c8` for black),
- a promotion is written as `<from><to><promo-piece>` (e.g. `e7e8q`),
- an en passant capture is written with the pawn's landing square (e.g. `e5d6`).

All piece captures are written the same way (from + to squares only; no `x`).

Write `/app/moves.json`:

```json
{
  "<id>": ["<every legal move in UCI, sorted alphabetically>", ...],
  ...
}
```

Then run your script so `/app/moves.json` is produced. The `python-chess` library is installed; it can generate the oracle legal-move set (`board.legal_moves`), or you may implement move generation yourself.
# SAN extensions validation

`/app/moves.txt` contains one chess-move token per line (no other text). Each token is written in **Standard Algebraic Notation (SAN)** with common extensions: optional castling tokens, capture `x`, promotion `=[QRBN]`, result symbol `+` (check) or `#` (checkmate), and piece-disambiguation.

Write a Python program at `/app/validate_san.py` that classifies every token and writes the results to `/app/san_result.json`.

## Algorithm (apply in this order)

For each token `t`:

1. Determine the **result kind** by inspecting the trailing characters:
   - `t` ends with `#` &rarr; kind is `"checkmate"`, and the classification uses `t` with that final `#` removed.
   - `t` ends with `+` &rarr; kind is `"check"`, and the classification uses `t` with that final `+` removed.
   - otherwise kind is `"quiet"` and the whole token is classified.

2. Classify the (possibly suffix-stripped) token `s` as **valid** if and only if it **fully** matches any one of these three forms:
   - Castling: exactly `O-O` or `O-O-O`.
   - Pawn move/capture, regex `^[a-h]?x?[a-h][1-8](?:=[QRBN])?$`
   - Piece move, regex `^[KQRBN](?:x|[a-h1-8]x?)?[a-h][1-8]$`

   (Use Python's `re.fullmatch` semantics — the `^...$` anchors ensure the whole stripped token is consumed.)

3. If it matches any form, the token is `valid = true` and keeps its kind. Otherwise `valid = false` and kind should be `null`.

## Output format

Write `/app/san_result.json` containing exactly:

```json
{
  "results": [
    {"move": "<token as it appeared, with any + or # still present>", "valid": true|false, "kind": "quiet"|"check"|"checkmate"|null}
  ]
}
```

The `results` array must preserve the exact line order of `moves.txt` and include **every** line. The `move` field must be the original token including any trailing `+` or `#`.

Only the Python standard library is required (`re`, `json`). Create the script and run it so `/app/san_result.json` is produced on disk.
# umber-gasket fixtures

- `sample_start.fen` — a beginning FEN with exactly one white knight on an
  otherwise empty board. Use it to sanity-check `/app/moves.fen.rules`.
- `sample.m` — a tiny M program showing `(define (lambda ...))`, relayed stdin
  via `(read-int)`/`(eof?)`, and `(print ...)`. Run with
  `printf 'path\n2\n3\n4\n' | python3 /app/eval.py`.

The full contracts for all four deliverables are in `instruction.md`.

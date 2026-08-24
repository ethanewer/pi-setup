You are given `/app/compiler.py`, a tiny toy "compiler/evaluator" for simple arithmetic expressions over non-negative integers, and `/app/src.txt`, a source file with one expression on every line.

The toy compiler currently applies every operator strictly left-to-right and completely ignores parentheses. Because of this it produces wrong results for expressions that mix `*` with `+`/`-`, and for expressions containing parentheses.

Fix `/app/compiler.py` so that its evaluator:
- respects standard precedence (`*` binds tighter than `+` and `-`),
- honors parentheses,
- produces the correct integer result for every line in `/app/src.txt`.

Do not change the file `/app/src.txt`. After fixing it, run `/app/compiler.py`. It must read each line of `/app/src.txt` and write one integer result per line to `/app/src_output.txt` (same order as input lines). The verifier recomputes the correct result of each expression independently and compares.

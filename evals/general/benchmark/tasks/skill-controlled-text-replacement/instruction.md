`/app/spec.txt` contains a text document. You must perform a **controlled** text replacement: replace every occurrence of the exact token `TODO` with the token `DONE`, but only when both of the following hold:

- The token `TODO` is bounded by word boundaries (i.e. not part of a longer word such as `TODAY`, `needTODOnow`, or `TODO_X`).
- The line does **not** contain the hidden marker `LOCK:ON` — those lines must be left completely unchanged.

Original line content example:
```
plan: TODO and TODO item - keep
submit TODAYS file
LOCK:ON TODO must stay
review TODOS and TODO
```
The last-but-one line (`LOCK:ON ...`) is untouched; the trailing TODOs after `LOCK:ON` are not replaced.

Write a program `/app/replace.py` that reads `/app/spec.txt`, applies the rule above to every line, and writes the result to `/app/out.txt`. Run it so `/app/out.txt` is produced. The verifier applies the same rule independently and compares byte-for-byte (ignoring trailing whitespace per line).
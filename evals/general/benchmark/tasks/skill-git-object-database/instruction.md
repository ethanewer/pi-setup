A Git repository exists at `/app/repo`. It tracks the file `seed/input.txt`, whose exact content is the single line:
```
object-db-probe-42
```

Git stores every file's content as a **blob** object in its internal object database. Each blob is addressed by the SHA-1 of a small header plus the raw content bytes.

Compute the blob object id Git assigns to that file. A simple way is to use plumbing that hashes file content as Git would:

```
git hash-object /app/repo/seed/input.txt
```

Write your result — the 40-character lower-case hex object name — to `/app/answer.txt` (and nothing else). The verifier independently runs the same hash computation on that file and compares it with `/app/answer.txt`.
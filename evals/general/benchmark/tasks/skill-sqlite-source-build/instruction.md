# Building SQLite from its C source

The SQLite public-domain source distribution, shipped as an **amalgamation**, is available at:

```
/app/sqlite_src/sqlite3.c      (the amalgamation: the entire SQLite library in one C file)
/app/sqlite_src/sqlite3.h      (the public API header)
/app/sqlite_src/shell.c        (the command-line shell / REPL)
```

A C compiler (`gcc`) is installed. Your task is to **build the `sqlite3` command-line program from this source**.

## 1. Build

Compile `shell.c` together with the `sqlite3.c` amalgamation into an executable named `/app/sqlite3`:

```bash
mkdir -p /app
gcc -DSQLITE_THREADSAFE=1 -o /app/sqlite3 /app/sqlite_src/shell.c /app/sqlite_src/sqlite3.c -lpthread -ldl -lm
```

(Compilation of the ~9 MB amalgamation takes roughly 30–90 seconds; let it finish. If the compiler complains about missing `-lm`/`-lpthread`/`-ldl`, keep all three linker flags.)

## 2. Use the built program

`/app/sales.db` is a SQLite database containing a `sales(item TEXT, qty INTEGER)` table with these rows:

```
apple 3, banana 5, apple 2, cherry 7, banana 1, apple 4
```

Using **your freshly built** `/app/sqlite3` executable, run this aggregation query against `/app/sales.db`:

```sql
SELECT item, SUM(qty) FROM sales GROUP BY item ORDER BY item;
```

Write the text output produced by the query into `/app/result.txt`, exactly as the tool prints it (the default column separator SQLite prints is `|`, so the answer is expected to look like `apple|9` etc.).

## 3. Verify the executable

The verifier checks that `/app/sqlite3` is a real, large compiled executable (not a stub), and then **uses the same** `/app/sqlite3` to run the identical query on `/app/sales.db`, requiring the output to contain the correct per-item totals and to match the contents of your `/app/result.txt`.
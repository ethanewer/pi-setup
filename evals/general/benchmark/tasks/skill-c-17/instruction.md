In `/app/data` there is a small directory tree of files and subdirectories (a few regular
files, e.g. `logs/a.log`, `reports/b.log`, plus a subdirectory `x/` containing more files;
exact layout:

```
/app/data/
  a.log        (content: abc)
  b.log        (content: hello)
  x/
    c.txt      (content: world!)
    empty.txt  (content: empty, 0 bytes)
```

Write a **C++17** program at `/app/treewalk.cpp` that uses **`std::filesystem`**
(recursive directory iteration) to walk `/app/data` (its root may be passed as `argv[1]`,
defaulting to `/app/data`), and prints for **every regular file** one line

```
name:size
```

using each file's **filename** and its **size in bytes**, followed by a final line

```
total=NNN
```

where `NNN` is the sum of all file sizes. Compile and run it with C++17 explicitly
enabled:

```bash
g++ -std=c++17 -O2 -o /app/treewalk /app/treewalk.cpp
/app/treewalk
```

Expected output for the shipped tree (order of the per-file lines is free):

```
total=14
```

(3 + 5 + 6 + 0 = 14). The verifier recompiles your source with `-std=c++17` and checks
that it both contains the `std::filesystem` API and that each per-file line and the
`total=` line match the real contents of `/app/data`.
#!/bin/bash
set -euo pipefail
mkdir -p /app

gcc -DSQLITE_THREADSAFE=1 -o /app/sqlite3 \
    /app/sqlite_src/shell.c /app/sqlite_src/sqlite3.c -lpthread -ldl -lm

/app/sqlite3 /app/sales.db \
    "SELECT item, SUM(qty) FROM sales GROUP BY item ORDER BY item;" \
    > /app/result.txt
# Meridian Freight — warehouse query desk

`original.sql` — the current production **Monthly Cost Report**. Operations
runs it on the first business day of each month, one tenant at a time. It
produces the exact numbers the finance team signs off, but it has always been
slow, and it gets slower every month as the warehouse grows.

The warehouse itself is described in `/app/warehouse/schema.sql`. The connection
details are in `instruction.md`.
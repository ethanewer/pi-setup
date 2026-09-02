# navd — crawler navigation daemon (read me)

Start the daemon:

    python3 /app/navd/navd.py /app/navd/grid.json 43770

- It listens on **127.0.0.1** only, on the port you give it.
- It prints `LISTENING <port>` on stdout when ready.
- Wire format: one **text command line** in, one **JSON line** out, then the
  daemon closes the connection. Exactly one request per connection.
- Commands: `PLAN` (reset to start, returns grid/start/goal/walls) and
  `STEP <N|S|E|W>` (advance the crawler; replies carry `"pos"`, `"moves"` and
  the `"status"`; the final arrival reply carries the `"token"`).
- Grid cells are `[row, col]`, 0-indexed, `row` grows southward. Walls are
  impassable. The full token formula is documented at the top of `navd.py`.

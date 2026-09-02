# Serial console UART log probe

`/app/uart.log` is a short capture from an embedded serial console. It contains
a header line, a number of `RX <hex>` frame lines, and a footer line. Each RX
frame line records one byte received over the UART, written as two hex digits
(`00`–`ff`).

Read `/app/uart.log` and compute three facts about it:

1. `num_frames` — the count of `RX` frame lines.
2. `max_byte` — the largest received byte value (decimal integer) across all RX
   frames.
3. `last_byte` — the byte value (decimal integer) of the **last** RX frame line
   in the file.

Write these to `/app/answer.json`:

```json
{
  "num_frames": 4,
  "max_byte": 31,
  "last_byte": 13
}
```

Compute the values from the actual file contents (`RX 1F` is byte `31` decimal,
`RX 0D` is `13` decimal, etc.). Use any simple parser you like.
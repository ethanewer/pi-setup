# Effective addressing computation

`/app/ea.txt` describes a set of memory-address expressions of the form used in assembly addressing modes:

```
EA = base + index * scale + displacement
```

In an instruction such as `mov eax, [EBX + ESI*8]`, the value `[EBX + ESI*8]` is the **effective address** (`EA`), where `base`, `index`, `scale` and an optional `disp` (displacement, default 0) are supplied. Compute the integer effective address (as an element of the memory address shape) for every line.

Read `/app/ea.txt`. Each line has the form:

```
EA<N> base=<b> index=<i> scale=<s> disp=<d>
```

Compute for each `EA<N>` the value `EA = base + index*scale + disp`, then write the results to `/app/answer.json`:

```json
{
  "ea1": 148,
  "ea2": 532,
  "ea3": 84
}
```

Use the `ea1`/`ea2`/... keys exactly as they appear on the lines (lowercase `ea` + number).
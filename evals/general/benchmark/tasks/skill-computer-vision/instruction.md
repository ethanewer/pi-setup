`/app/image.pgm` is a grayscale image in the **P2 (ASCII PGM)** raster format:

- first line: `P2`
- second line: `<width> <height>`
- third line: `255` (max value)
- remaining whitespace-separated integers: pixel intensity values in row-major order (0 = black, 255 = white).

Write a program `/app/analyze.py` that:
1. parses `/app/image.pgm` (the exact format above),
2. treats a pixel as "bright" when its intensity value is >= 128,
3. writes exactly four lines to `/app/report.txt`:
   - `width=<width>`
   - `height=<height>`
   - `bright=<number of bright pixels>`
   - `mean=<mean intensity rounded to 2 decimals>`

Run your program so `/app/report.txt` is produced. The verifier parses the same PGM, computes the four values independently, and compares them exactly.
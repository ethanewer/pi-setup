# Compare two PPM images

Two **P3 (plain-text) PPM** images are provided at `/app/a.ppm` and `/app/b.ppm`. They have identical dimensions and are almost identical: they differ only in a small number of pixels' red channel values.

Write a Python program `/app/compare.py` that:

1. Parses both PPM files (P3 format: a `P3` magic token, then width, height, max value, then width×height RGB triples as tokens; comments starting with `#` may appear after the magic number and must be skipped).
2. Computes, pixel-by-pixel, the absolute difference per channel (red, green, blue).
3. Counts the number of pixels where **any** channel differs (a "differing pixel").
4. Finds the **maximum absolute single-channel difference** across the whole image.
5. Prints exactly one line to stdout with the two integers separated by a space:
   `<num_differing_pixels> <max_absolute_channel_difference>`

Then run `/app/compare.py` and save its stdout to `/app/diff.txt`. The verifier recomputes both numbers from the two PPM files and checks that `/app/diff.txt` matches exactly.
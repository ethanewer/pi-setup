`/app/img_norm.png` is a 4×4 8-bit grayscale (mode `L`) PNG image with integer pixel values in `[0, 255]`. Use **Pillow** and **NumPy** to normalize it.

Write `/app/normalize.py`, which:
1. loads the image and converts it to grayscale: `np.asarray(Image.open('/app/img_norm.png').convert('L'), dtype=float)`,
2. normalizes each pixel to `[0.0, 1.0]` by dividing by `255.0`,
3. computes the mean of all normalized pixel values,
4. writes the mean formatted to 4 decimal places (e.g. `0.4750`) to `/app/norm.txt` (a single line, trailing newline allowed).

Run `/app/normalize.py`. The verifier applies the identical computation to the same image, so file format is the only requirement.

The verifier compares `/app/norm.txt` to its own mean over the same normalized pixels.
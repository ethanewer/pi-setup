`/app/img_info.png` is a small RGB PNG image. Use the **Pillow** library to inspect it.

Write `/app/inspect.py`, which:
1. opens `/app/img_info.png` with `Image.open`,
2. reads its width (pixels), height (pixels), and mode (`mode` attribute),
3. reads the RGB value of the pixel at `(x=3, y=3)` via `img.getpixel((3, 3))`,
4. writes `/app/image_info.txt` as four lines, in this exact order:
   - line 1: width (integer)
   - line 2: height (integer)
   - line 3: mode (string)
   - line 4: the pixel as `R,G,B` with no spaces

Run `/app/inspect.py`. The expected output for `/app/image_info.txt` is:
```
8
8
RGB
120,60,200
```

The verifier inspects the same image with Pillow and compares the four lines.
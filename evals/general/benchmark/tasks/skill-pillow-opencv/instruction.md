# Image resize with Pillow

`/app/photo.png` is a PNG image, 400 pixels wide and 300 pixels tall.

Use **Pillow** (the `PIL` module) — or OpenCV if you prefer — to load it and
**resize it while preserving the aspect ratio** so that its **width becomes
160 pixels** (the height must shrink by the same ratio: `new_height =
round(160 * original_height / original_width)`).

Save the resized image to `/app/resized.png` (PNG format).

When done, confirm `/app/resized.png` exists and is a valid PNG whose dimensions
are exactly 160 × 120 pixels.
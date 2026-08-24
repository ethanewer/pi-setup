# Pillow/OpenCV: count green pixels

`/app/circle.png` is a **200x200 RGB image**: a white background (255,255,255) with a
single **solid green filled circle** (pure green `(0,255,0)` in RGB) at the centre.

Write a Python script `/app/green_count.py` that uses **Pillow** (and optionally NumPy)
to load the image and count the pixels that are (approximately) pure green:

- `from PIL import Image; img = Image.open('/app/circle.png').convert('RGB')`
- convert to a NumPy array (`arr = numpy.asarray(img)`), then build a boolean mask for
  pixels where the green channel is high and red/blue are low, e.g.
  `(arr[:,:,1] > 200) & (arr[:,:,0] < 50) & (arr[:,:,2] < 50)`, and
  count with `.sum()`.

(OpenCV's `cv2` / `numpy` are also installed; you may use whichever you prefer, but the
loading must be via the Pillow/OpenCV image API.)

Write the integer count to `/app/green_count.txt` (as text). The verifier recomputes the
expected count from the same image independently and compares.
# OpenCV: count red pixels

`/app/shapes.png` is a **200x200 RGB image**: a white background (255,255,255) with a
single **solid red rectangle** drawn on it. (In OpenCV's BGR channel order the red
pixels are `(B=0, G=0, R=255)`; the white background is `(255,255,255)`.)

Write a Python script `/app/red_count.py` that uses **OpenCV** (`cv2`) to count the
number of pixels that are (approximately) pure red:

1. `img = cv2.imread('/app/shapes.png')`
2. build a color mask with `cv2.inRange(img, lower, upper)` where the bounds only
   include red pixels (e.g. `lower = (0, 0, 200)`, `upper = (100, 100, 255)`),
3. count with `cv2.countNonZero(mask)`.

Write the integer count to `/app/red_count.txt` (as text, e.g. `3600`). The verifier
recomputes the expected count from the same image with OpenCV and compares.
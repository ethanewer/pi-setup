`/app/img_a.png` and `/app/img_b.png` are two 8×8 8-bit grayscale (mode `L`) PNG images. Use **Pillow** and **NumPy** to measure their similarity.

Write `/app/similarity.py`, which:
1. loads both images and converts to grayscale float arrays: `np.asarray(Image.open(p).convert('L'), dtype=float).flatten()`,
2. computes the **cosine similarity** of the two flattened vectors:
   `cos = dot(a, b) / (norm(a) * norm(b))`,
3. writes the cosine similarity rounded/truncated to 4 decimal places (e.g. `0.9479`) to `/app/cosine_similarity.txt` (a single line, trailing newline allowed).

Run `/app/similarity.py`. The verifier recomputes the same cosine similarity from the same two images and compares.
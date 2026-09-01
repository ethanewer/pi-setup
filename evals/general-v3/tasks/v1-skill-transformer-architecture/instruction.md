A transformer uses scaled dot-product attention. For query, key, and value matrices Q, K, V the attention output is:

    Attention(Q, K, V) = softmax(Q·Kᵀ / √dₖ) · V

where dₖ is the key dimension (here dₖ = 3) and softmax is applied row-wise.

In `/app` there is a Python module `attn_input.py` defining three 3×3 lists of floats: `Q`, `K`, and `V`.

Write `/app/attention.py` that:
1. imports `Q`, `K`, `V` from `/app/attn_input.py`,
2. computes the scaled dot-product attention output exactly as described (treating the matrices as lists of lists; use `math.exp` for softmax, and `math.sqrt(dk)` for the scaling),
3. writes the resulting 3×3 output matrix to `/app/attention.json` as a JSON list-of-lists of numbers, each rounded to 6 decimal places.

Then run your script so that `/app/attention.json` is produced with the correct contents.
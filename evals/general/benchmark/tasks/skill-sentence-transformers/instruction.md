# Sentence embeddings with SentenceTransformers

The container already has the `sentence-transformers` library (with PyTorch)
installed, and an **offline snapshot** of the `BAAI/bge-small-zh-v1.5` model is
bundled at `/app/model_cache/` (config, tokenizer, `model.safetensors`, pooling
and `modules.json`). Load it from this local path — do **not** download
anything.

`/app/sentences.txt` is UTF-8 and contains exactly **two lines**: one Chinese
sentence on line 1 (`a`) and one on line 2 (`b`).

Write a Python script `/app/similarity.py` that:

1. Builds a `SentenceTransformer` from the local path `/app/model_cache`.
2. Encodes sentences `a` and `b` with `normalize_embeddings=True` and a modest
   `batch_size` (e.g. 16), using **no** query-instruction prefix for either.
3. Computes the cosine similarity between the two normalized vectors as their
   dot product.
4. Writes `/app/similarity.json` containing exactly:

```json
{"cosine_similarity": X}
```

where `X` is the similarity rounded to **4 decimal places**.

Run the script so `/app/similarity.json` exists. The verifier re-embeds the same
two sentences with the same model and procedure and accepts any value within
0.0001 of its own computed similarity.
# Word embeddings: mean pooling and cosine similarity

`/app/embeddings.json` contains a tiny pre-trained embedding model:

```json
{
  "dim": 4,
  "words": { "<word>": [<4 floats>], ... },
  "sentences": {
    "A": ["the", "cat", "chase", "the", "dog"],
    "B": ["the", "bird", "fly", "the", "fish"]
  }
}
```

Every word in `words` maps to a fixed 4-dimensional float vector. A sentence
is embedded by **mean pooling**: average the vectors of its tokens,
component-wise (a token not present in `words` contributes the zero vector).

The similarity of two sentence embeddings `a` and `b` is their **cosine
similarity**:

```
cos(a, b) = (a . b) / (||a|| * ||b||)
```

## Task

Write a Python 3 script `/app/embed.py` that:

1. Loads `/app/embeddings.json`.
2. Computes the mean-pooled embeddings of sentences `A` and `B`.
3. Computes their cosine similarity.
4. Writes `/app/answer.txt` containing exactly one line:

```
cosine_similarity=0.6615
```

i.e. the similarity rounded to 4 decimal places.  Run the script so
`/app/answer.txt` exists. The verifier recomputes the same value from
`/app/embeddings.json` with pure-Python floating point and accepts your value
within ±0.0005 (rounding tolerance).

(Values above are illustrative — compute the real one. Do not add any other
content to `/app/answer.txt`.)
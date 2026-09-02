# FastText word-vector model

`/app/model.vec` is a word-vector file in the standard FastText text export
format:

- Line 1: two integers `<vocab_size> <dim>`.
- The next `<vocab_size>` lines each contain a word followed by `<dim>`
  space-separated float values: the word's embedding vector.

The file contains these words (dim = 5):

```
king 0.2 0.1 0.0 0.0 0.0
queen 0.0 0.0 0.2 0.1 0.0
man 0.20 0.10 0.0 0.0 0.0
woman 0.0 0.0 0.2 0.1 0.0
apple 1.0 0.0 0.0 0.0 0.0
banana 0.0 2.0 0.0 0.0 0.0
```

## Your task

Write a Python 3 script `/app/fasttext.py` that:

1. reads `/app/model.vec`,
2. extracts the vocabulary (list of words, in file order) and dimension,
3. computes the vector of the word `queen`,
4. finds the *closest other word* to `queen` among all other words in the
   vocabulary, using cosine similarity (higher is closer; if two other words
   tie, pick the one appearing first in the file).
5. writes `/app/similar.json` with exactly:
   ```json
   {"vocab_size": 6, "dim": 5, "queen_vector": [0.0,0.0,0.2,0.1,0.0], "nearest": "woman"}
   ```

Round each element of `queen_vector` to 4 decimal places. Run the script so the
JSON exists. The verifier parses the same file independently and checks.
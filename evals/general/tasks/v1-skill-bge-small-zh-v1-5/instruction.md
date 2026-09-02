`/app/embed.json` holds text embedding data. It is a JSON object:
```json
{"sentences": ["...zh sentence...", ...],
 "embeddings": [[...768 floats...], ...]}
```
The `sentences` and `embeddings` arrays are parallel. The embedding vectors are 768-dimensional real-valued vectors such as the ones produced by the BGE model class (a common Chinese sentence-embedding model family). Use them exactly as given.

Write a program `/app/find_closest.py` that:
1. loads `/app/embed.json`,
2. for each sentence index `i`, computes the cosine similarity between its embedding and every other sentence's embedding (the one with the largest score), choosing, in case of an exact tie, the candidate with the *lower* sentence index,
3. writes `/app/similarity.json` as a JSON list in the same order as `sentences`, where every entry is:
   `{"sentence": <the source sentence>, "closest": <the most similar other sentence>, "score": <cosine similarity rounded to 4 decimal places>}`

Run your program to produce the output. The verifier recomputes the same values from `/app/embed.json`.

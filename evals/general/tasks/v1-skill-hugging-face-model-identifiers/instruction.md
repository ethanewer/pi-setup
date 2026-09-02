`/app/models.json` is a list of model descriptions, each with an organization (`org`) and a model repository name (`name`). This tracks the **Hugging Face model identifier** convention: a canonical HF model id is exactly `org/name`, using the literal casing and characters from the record.

Write `/app/ids.py`, which:
1. reads `/app/models.json`,
2. for each record builds the canonical Hugging Face identifier `org/name` (a plain string concatenation with a single `/`),
3. verifies every identifier matches the valid-repo-id pattern `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`,
4. writes `/app/ids.txt` with one identifier per line, in input order.

The file `/app/models.json` is:
```json
[
  {"org": "huggingface", "name": "bert-base-uncased"},
  {"org": "BAAI", "name": "bge-small-en-v1.5"},
  {"org": "bigscience", "name": "bloom-560m"}
]
```

Run `/app/ids.py`. The expected `/app/ids.txt` is:
```
huggingface/bert-base-uncased
BAAI/bge-small-en-v1.5
bigscience/bloom-560m
```

The verifier recomputes the same identifiers from the file.
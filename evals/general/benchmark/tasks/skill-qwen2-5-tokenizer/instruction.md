# Byte-level BPE tokenization (Qwen2.5-style)

`/app/tokenizer/tokenizer.json` holds a pre-trained, self-contained **byte-level BPE tokenizer** in the style used by Qwen2.5 (a `tokenizers` library `Tokenizer` serialized to JSON). It is already a trained model — vocab and merge rules are embedded in the file.

`/app/text.txt` contains a short plain sentence:
```
A quick brown fox tokenizes into pieces today.
```

Your task:
1. Load the tokenizer with the Python `tokenizers` library: `from tokenizers import Tokenizer; tok = Tokenizer.from_file("/app/tokenizer/tokenizer.json")`.
2. Encode the contents of `/app/text.txt` with `tok.encode(...)`, and take the number of tokens = `len(ids)` of that encoding.
3. Write **only the integer token count** to `/app/answer.txt` (bare number, no extra text).

Write the script as `/app/tokenize.py` and run it so `/app/answer.txt` is produced. The count is deterministic for a given tokenizer state.

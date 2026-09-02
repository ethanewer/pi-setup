`/app/tiny_model/` is a local, fully self-contained tiny BERT tokenizer directory (vocab + tokenizer config + special-tokens map). It uses no network and loads purely from disk.

Use the **Hugging Face `transformers` library** to load it and tokenize a phrase.

Write `/app/run.py`, which:
1. loads the tokenizer with `AutoTokenizer.from_pretrained('/app/tiny_model')`,
2. tokenizes the text `"hello world"` (note: the tokenizer lowercases input by default, and its vocabulary contains whole-token entries `hello` and `world`),
3. writes the resulting `input_ids` list — a JSON array of integers — to `/app/toks.json`.

The vocabulary file `/app/tiny_model/vocab.txt` is:
```
[PAD]
[UNK]
[CLS]
[SEP]
[MASK]
hello
fine
world
day
```

Run `/app/run.py` so `/app/toks.json` is produced. For `"hello world"` the expected ids are `[2, 5, 7, 3]` (`[CLS]`, `hello`, `world`, `[SEP]`). The verifier loads the same local tokenizer and compares.
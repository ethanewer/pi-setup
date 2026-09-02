# skill-tokenizers — tokenize a text and emit the token list

`/app/sample.txt` is a short English sentence. Your job: tokenize it and write
the resulting token sequence to `/app/tokens.json`.

## Tokenization rule (exact — the grader recomputes the same way)

Using the regular expression

```
[A-Za-z0-9]+|[^A-Za-z0-9]
```

against the whole file content gives a sequence of non-overlapping tokens in
order:
- runs of letters/digits → one token (e.g. `The`, `3`, `fox`),
- any single other character (space, punctuation, `=`, `+`) → a token.

So `tokens = re.findall(r"[A-Za-z0-9]+|[^A-Za-z0-9]", text)` where `text` is the
raw file contents (do **not** strip trailing newline before tokenizing; the
trailing newline becomes one token `\n`).

## Output

Write `/app/tokens.json`:

```json
{ "tokens": ["The", " ", "quick", ...], "count": <len(tokens)> }
```

`count` is the number of tokens.

## Success criteria

The grader recomputes the token list from `/app/sample.txt` with the same
regex and requires `tokens` and `count` to match exactly.
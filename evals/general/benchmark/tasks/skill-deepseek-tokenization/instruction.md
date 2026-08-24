The DeepSeek tokenizer is a Byte Pair Encoding (BPE) tokenizer: it starts from individual characters and repeatedly merges adjacent token pairs according to a learned merge table. This task reproduces that core step with a small, self-contained merge table.

Files:
- `/app/merges.txt` — merge table. Each line is `<t1> <t2> <new-token>` (space separated). The **line order defines priority**: a pair listed in an earlier line has higher rank than one in a later line.
- `/app/text_src.txt` — the text to tokenize (plain text, may contain spaces).

Write `/app/tokenizer.py` that applies this well-defined tokenization algorithm:

1. Represent the text as a flat list of tokens; initially every character (including the space character `" "`) is its own token.
2. Repeat until no adjacent token pair in the list appears as a begin pair in any merge line:
   a. Look at all adjacent token pairs in the current list.
   b. Among those adjacent pairs that appear as `<t1> <t2>` of some merge line, pick the pair with the **highest priority** (i.e. listed earliest in `merges.txt`).
   c. Replace **every** occurrence of that adjacent pair (anywhere in the list) with the merge line's `<new-token>`.
3. Write `/app/tokens.json`:
   ```json
   {"tokens": ["<token>", ...], "count": <number of tokens>}
   ```
   where `tokens` lists the final tokens in order and `count` is `len(tokens)`. Treat the space character as a distinct token in the output list and in the count.

Merges never combine the space token with anything, and every `<new-token>` is distinct from `a`/`b`, so the process terminates. Use only the Python standard library. Run your script so `/app/tokens.json` exists; the verifier applies the identical algorithm to the same files and compares.

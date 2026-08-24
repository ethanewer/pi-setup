This task exercises **byte-level BPE** tokenization as used by GPT-2: a sequence of base byte-tokens is repeatedly re-written by applying a fixed ordered list of merge rules, where merging two adjacent tokens replaces them with a single new token named by concatenating the two.

Inputs:

- `/app/tokens.txt` — a single line of whitespace-separated byte tokens:
  ```
  a b c d a b c d
  ```
- `/app/merges.txt` — one merge per line, in **priority order** (earlier lines are applied first). Each line lists two tokens separated by a space, meaning: whenever those two tokens are adjacent in the current sequence, replace the pair with a single token whose name is their concatenation.

The procedure: take the byte token sequence; for each merge in the file order, repeatedly find and merge **all non-overlapping adjacent occurrences** of that pair (left to right), replacing each with the single concatenated token; then move to the next merge.

Apply the merges to the token sequence and write the final merged tokens to `/app/answer.txt` as a single line, tokens separated by a single space.

The verifier independently applies the same Byte-Pair-Encoding procedure to the same inputs and compares the result.
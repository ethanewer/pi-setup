# Recognising AWS and GitHub credential tokens

`/app/tokens.txt` contains credential-like strings, one per line. Classify each line by its format pattern, using well-known AWS and GitHub token shapes:

- **aws_account**: an AWS **access key ID** — starts with the prefix `AKIA` followed by exactly 16 base-32 characters from `[A-Z0-9]` (total length so full 20 characters, all uppercase letters/digits).
- **aws_secret**: an AWS **secret access key** — exactly 40 characters from `[A-Za-z0-9]` plus possibly `/`, `+`, `=` (total length exactly 40).
- **github**: a GitHub personal-access token — the prefix `ghp_`, `gho_`, `ghu_`, `ghs_` or `ghr_` followed by 24 or more characters from `[A-Za-z0-9_]`.
- **other**: anything that matches none of the above.

Order of checks matters: check the `AKIA` regex first, then the 40-char secret regex, then the GitHub prefix regex, then classify as `other`.

## Task

Read every non-empty line of `/app/tokens.txt` in order and write `/app/answer.json` as a **JSON array** of objects, preserving line order:

```json
[
  {"value": "AKIAEXAMPLEKEY000001", "type": "aws_access"},
  {"value": "EXAMPLESECRETKEYEXAMPLESECRETKEYEXAMPLE0", "type": "aws_secret"},
  {"value": "ghp_", "type": "github"},
  {"value": "nope", "type": "other"}
]
```

Use one entry per line, with `value` = the exact original token string and `type` one of `aws_access`, `aws_secret`, `github`, `other`.
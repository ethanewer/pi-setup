# Scan a small codebase for a leaked secret

## Context

`/app/repo/` is a small application directory tree. One of the files contains a
**committed secret**: a live API key that should never be in source control.
Scan the files, locate the leaked credential, and report it.

## Your task

1. Inspect every file under `/app/repo/` (plain text; look for keys like
   `KEY=`, `password:`, `token`, long alphanumeric values). Identify the file
   that contains the committed live API key (format: `token_EXAMPLE_...`).
2. Write `/app/report/secret.json`:

   ```json
   {
     "file": "<path relative to /app, e.g. repo/config/secrets.env>",
     "key":  "<the variable/field name holding the secret>",
     "secret": "<the secret value>"
   }
   ```

## Success criteria

- `/app/report/secret.json` is valid JSON.
- `file`, `key`, and `secret` match the actual leaked credential exactly.
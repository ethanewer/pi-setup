A web handler builds an HTTP `Set-Cookie` header from user-controlled cookie data. If attacker-controlled data contains a Carriage Return (`\r`) or Line Feed (`\n`), an attacker can inject additional HTTP headers (CRLF / response-splitting, CWE-93). The fix is to strip CR/LF before the value is placed in a header.

Write `/app/cwe.py` with:

```python
def sanitize(value: str) -> str:
    ...
```

`sanitize` must return the input with **every** Carriage Return (`\r`) and Line Feed (`\n`) character removed, leaving all other characters unchanged.

Then:
1. Read `/app/threat.txt` as latin-1 text (so `\r` and `\n` are preserved as characters).
2. Apply `sanitize` to its contents.
3. Write only the sanitized result to `/app/safe_cookie.txt`.

Run your script so the output file is created. The verifier imports `sanitize` and confirms it strips CR/LF from several obvious attack payloads, and that `/app/safe_cookie.txt` contains no CR or LF characters.
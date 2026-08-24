# Digital forensics: identify a file and recover hidden trailing data

You have been given a single evidence file: `/app/evidence.bin`. It is a
well-formed file of a common image format, but a forensic examiner suspects
extra bytes were **appended after the end of the file's normal data stream**
(file slack / appended data) — a common hiding trick.

## Task

Perform basic digital forensics on `/app/evidence.bin` and produce two outputs:

1. **File type identification** — write the lowercase file-format name of the
   image (as indicated by its **magic bytes** at the very start of the file)
   to `/app/file_type.txt`. The magic signature of this format starts with the
   bytes `89 50 4E 47` (hex) followed by `0D 0A 1A 0A`.

2. **Recovery** — extract the hidden token string that has been appended after
   the end of the image data, and write it verbatim to `/app/flag.txt`.

## Hints (techniques you may use)

- Inspect the file with any tool you like: `xxd`, `hexdump`, `od`, or Python 3
  (`open(..., 'rb').read()` and byte/hex searches). Note: not all CLI hex tools
  are preinstalled — Python 3 always works.
- The image's byte stream ends with an **IEND** chunk, after which the appended
  data begins. `strings`-style scanning or searching for printable ASCII runs in
  the trailing bytes will reveal the token.

The hidden token is a `df-token-`-prefixed ASCII string of fixed length. The
verifier checks that `/app/file_type.txt` contains the image format name and
that `/app/flag.txt` contains the exact hidden token.
`/app/blob.bin` is a binary file: it begins with several non-printable bytes and contains a printable alphabetic **token** embedded inside surrounding binary/junk bytes.

Use hex and string inspection tools to locate and recover that printable token. Command-line tools such as `strings`, `xxd`, `hexdump`, or `grep -a` are all available.

Write the exact token (a single contiguous run of printable ASCII characters) to `/app/token.txt`, with nothing else.

The verifier independently extracts the same printable run from `/app/blob.bin` and compares it with `/app/token.txt`.
`/app/plain.txt` contains the text: `Echoes of the canyon at midnight - ZQ-44`.

Write a program `/app/roundtrip.py` that:
1. reads `/app/plain.txt` as bytes,
2. compresses it (losslessly) with the **gzip** format and writes the compressed bytes to `/app/payload.gz`,
3. opens and decompresses `/app/payload.gz` back to bytes,
4. verifies that the decompressed bytes equal the original bytes of `/app/plain.txt`,
5. writes the decompressed bytes to `/app/recovered.txt` (the write must only happen after the round trip is confirmed to match).

Run your program so both `/app/payload.gz` and `/app/recovered.txt` are produced. The verifier independently decompresses `/app/payload.gz` and checks that `/app/recovered.txt` matches the original `/app/plain.txt` content.
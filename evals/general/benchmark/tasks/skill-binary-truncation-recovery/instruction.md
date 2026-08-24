`/app/truncated.bin` is a file that was cut short (truncated) — part of its tail is missing. You must recover the complete original file using the file format and the intact header.

Format of the original file:
- bytes 0..3: ASCII magic `BINF`
- bytes 4..7: unsigned 32-bit little-endian integer L = the total length (in bytes) of the *original, untruncated* file
- bytes 8..L-1: the payload. Payload byte at relative index k (where k = byte_position - 8, starting at 0) always equals `k % 256`. In other words the payload is a deterministic repeating byte sequence `0,1,2,...,255,0,1,...`.

The file at `/app/truncated.bin` is the beginning of that original file. Its header is intact, but the trailing payload bytes are missing.

Write a program `/app/recover.py` that:
1. reads `/app/truncated.bin`,
2. reads L from the header and the bytes that are present,
3. reconstructs the full original file (header plus the complete payload of length L-8, filling in missing bytes with the pattern `(k % 256)`),
4. writes the recovered full file to `/app/recovered.bin`.

The verifier reconstructs the same full file from the same format and compares it byte-for-byte to `/app/recovered.bin`.

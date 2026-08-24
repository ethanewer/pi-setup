A file `/app/data.xor` contains the bytes of a readable ASCII message that was XOR-encrypted with a **single unknown key byte** (each plaintext byte was XORed with the same key value).

Recover the plaintext. Write `/app/recover.py` that:
1. reads `/app/data.xor` as bytes,
2. brute-forces all 256 possible single-byte keys (0–255),
3. for each key, decodes the whole file by XORing every byte with that key,
4. selects the key whose decoded output consists entirely of **uppercase letters (A–Z, bytes 65–90) and spaces** — the known charset of the original message,
5. writes the recovered plaintext (as a string) to `/app/recovered.txt`.

Then run your script so that `/app/recovered.txt` is produced. Its content must equal the original plaintext.
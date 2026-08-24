# Known-plaintext pairs (Caesar cipher)

Three files are provided:

- `/app/known_plain.txt` — a known plaintext, e.g. `HELLOWORLD`
- `/app/known_cipher.txt` — the corresponding ciphertext under a **Caesar shift cipher** (each letter shifted forward by the same amount, wrapping around the alphabet)
- `/app/ciphertext.txt` — a second message encrypted with the **same** key

Your task:

1. Derive the shift key `k` (an integer in 0..25) from the known-plaintext pair: for a reference letter position, `cipher = (plain + k) mod 26`. Use the first letter or any consistent letter to compute `k`.
2. Decrypt `/app/ciphertext.txt` with that key to recover the plaintext.
3. Write the recovered uppercase plaintext to `/app/decoded.txt`, ending with a newline.

Only `A-Z` letters are shiftable; spaces and punctuation are preserved as-is (the corpus below contains none). The plaintext is uppercase English.

Implementation hint:

```python
def shift_char(c, k):
    if 'A' <= c <= 'Z':
        return chr((ord(c) - ord('A') + k) % 26 + ord('A'))
    return c

def caesar(s, k):
    return ''.join(shift_char(c, k) for c in s)

p = open('/app/known_plain.txt').read().strip()
c = open('/app/known_cipher.txt').read().strip()
k = (ord(c[0]) - ord(p[0])) % 26          # derive key from first letters
ct = open('/app/ciphertext.txt').read().strip()
dec = caesar(ct, -k)                        # decrypt by shifting backwards
open('/app/decoded.txt', 'w').write(dec + '\n')
```

Afterward `/app/decoded.txt` must contain the correctly decrypted plaintext.
`/app/oracle` is a black-box encryption oracle. It accepts commands via its first argument:

- `oracle enc <hex-plaintext>` — encrypts the given plaintext (hex string, even length) and prints the ciphertext as a hex string.
- `oracle flag` — prints the hex ciphertext of a hidden secret flag.

Internally the oracle encrypts a plaintext `P` (of any length `L`, bytes `P[0..L-1]`) as:

```
C[i] = P[i] XOR KEY[i mod 16]     for i = 0 .. L-1
```

where `KEY` is a fixed, secret 16-byte key string (`KEY[0..15]`) that you do not directly know. Encryption is thus a **periodically repeating key** with a 16-byte period.

Because you get to choose the plaintext that is encrypted (this is a **chosen-plaintext attack**), you can learn `KEY` and then decrypt the flag:

1. Choose a plaintext of sixteen zero bytes (`0000...`). Since `C[i] = 0 XOR KEY[i]`, the returned 16 ciphertext bytes equal `KEY` exactly. Recover `KEY`.
2. Ask the oracle for the flag ciphertext.
3. Decrypt it: `P[i] = C[i] XOR KEY[i mod 16]` for each byte.

Write the recovered flag **as a plain ASCII string** (not hex) to `/app/flag.txt` with no trailing newline. Then run your script so `/app/flag.txt` is produced.

You may implement the attack in a script. Everything is pure byte arithmetic; no extra libraries are required.
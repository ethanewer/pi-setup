# RSA-2048 encryption

`/app/message.txt` contains a short plaintext secret (a single line ending in a newline).
`/app/public.pem` is an **RSA-2048 public key** in PEM format (PKCS#1, 2048-bit modulus).

Encrypt `/app/message.txt` with RSA (2048-bit, OAEP padding) using the provided public key,
and write the resulting ciphertext to `/app/message.enc`.

Use OpenSSL. The recommended command shape is:

```
openssl pkeyutl -encrypt -pubin -inkey /app/public.pem -in /app/message.txt \
     -out /app/message.enc -pkeyopt rsa_padding_mode:oaep
```

Run the command so that `/app/message.enc` exists and contains a valid OAEP ciphertext
that decrypts back to the original plaintext. You may use any RSA-2048 padding mode as
long as the verifier's corresponding decrypt call recovers the plaintext; OAEP is the
standard choice. Leave `/app/message.enc` in place when done.
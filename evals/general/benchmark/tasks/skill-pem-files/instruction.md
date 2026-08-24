# Inspect a PEM-encoded public key

`/app/certificate.pem` is a **PEM**-encoded file (`-----BEGIN PUBLIC KEY----- ...`).
It contains an RSA **public key** encoded in the PKCS#1/X.509 SubjectPublicKeyInfo
format.

Use the `cryptography` Python library to parse this PEM file and inspect the key:

```python
from cryptography.hazmat.primitives.serialization import load_pem_public_key
key = load_pem_public_key(open('/app/certificate.pem', 'rb').read())
```

Determine the RSA **public exponent** `e` (available as
`key.public_numbers().e`). It is a positive integer.

Write that integer in decimal form (no whitespace, no `0x` prefix) to
`/app/answer.txt`, followed by a single newline.

When done, confirm `/app/answer.txt` exists and contains exactly the public exponent
as a plain decimal integer.
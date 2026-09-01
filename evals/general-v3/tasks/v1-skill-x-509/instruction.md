Using **OpenSSL**, generate a self-signed **X.509** certificate and write it to `/app/cert.pem`.

Requirements:
- The certificate subject must have **common name (CN) = example.com**.
- It must be a self-signed certificate (issuer == subject == the key you generate).
- Validity: generate it so it is valid for 365 days.
- It must be a valid X.509 certificate that `openssl x509 -in /app/cert.pem -noout` can parse.

Additionally, write the private key to `/app/key.pem` (PEM format, unencrypted). A concise way to do this is `openssl req -x509 -newkey rsa:2048 ...`. Your `/app/cert.pem` is what will be checked: it must be a parseable X.509 certificate whose subject contains `CN=example.com`.
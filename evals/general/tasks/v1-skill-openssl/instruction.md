# OpenSSL: self-signed certificate and its fingerprint

Use **OpenSSL** to create a self-signed **X.509** certificate.

1. Create a directory `/app/certs` and generate a fresh self-signed certificate there.
   Its subject **common name (CN)** must be `internal.host`. A concise way is:

   ```bash
   mkdir -p /app/certs
   openssl req -x509 -newkey rsa:2048 -nodes \
     -keyout /app/certs/key.pem -out /app/certs/cert.pem \
     -days 365 -subj "/CN=internal.host"
   ```

2. Compute the certificate's **SHA-256 fingerprint** with OpenSSL:

   ```bash
   openssl x509 -in /app/certs/cert.pem -noout -fingerprint -sha256
   ```

   That prints a line like `SHA256 Fingerprint=AB:1C:...` (colon-separated hex bytes).
   Extract only the hex part (drop the prefix `SHA256 Fingerprint=`), convert it to
   **lowercase**, and write it to `/app/fingerprint.txt` (with the trailing newline).

   For example: `openssl x509 -in /app/certs/cert.pem -noout -fingerprint -sha256 \
     | sed 's/.*=//' | tr 'A-F' 'a-f'` would produce the hex needed.

The verifier parses `/app/certs/cert.pem` with OpenSSL, recomputes the SHA-256
fingerprint, normalizes it the same way, and compares it to `/app/fingerprint.txt`.
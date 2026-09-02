# Inspect a TLS server certificate

## Context

`/app/cert.pem` is a PEM-encoded X.509 certificate (self-signed). Inspect it
with `openssl` and report its subject, common name, and validity period.

## Your task

1. Use openssl to decode the certificate:
   `openssl x509 -in /app/cert.pem -noout -subject -dates`
2. Record the subject (`...CN=...`), the common name (the `CN` value), and the
   `notBefore` / `notAfter` validity timestamps (the exact strings reported by
   openssl).
3. Write `/app/out/cert_info.json`:

   ```json
   {
     "subject": "<subject line>",
     "cn": "<common name>",
     "not_before": "<notBefore timestamp string>",
     "not_after": "<notAfter timestamp string>"
   }
   ```

## Success criteria

- `/app/out/cert_info.json` exists and is valid JSON.
- `subject`, `CN`, `not_before`, `not_after` match what `openssl x509 -noout
  -subject -dates` reports for `/app/cert.pem`.
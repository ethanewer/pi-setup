# TLS certificate inspection: read a PEM-encoded X.509 server certificate

`/app/tls/server.pem` is a self-signed X.509 server certificate in
**PEM (ASCII base64) encoding**. Its issuer and subject were set when it was
generated.

Your task: decode the certificate and report the **Common Name (CN)** recorded
in its **Subject** field.

The `openssl` command-line tool is available in this environment. A convenient
inspection command is:

```
openssl x509 -in /app/tls/server.pem -noout -subject
```

which prints the certificate's subject in the form
`subject= /C=US/ST=California/O=HarborBench/CN=internal.probe.example`.

The **Common Name** is the `CN=` attribute value in that subject line.

Write **only** the Common Name string (the exact `CN=` value, with no other
subject attributes, no `CN=` prefix, and no surrounding quotes or whitespace)
to `/app/answer.txt`.

For example, if the subject were `CN=foo.example.com`, then `/app/answer.txt`
must contain exactly the 16 characters `foo.example.com`.
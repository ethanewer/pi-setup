A local HTTP server tool is available (Python's `http.server` is installed). `/app/webroot` is intended to be the document root.

Your goal is to fetch the resource `public/sample.json` from a local HTTP server **over HTTP using curl**, and save the raw response body to `/app/fetched.json`.

Steps:
1. Start a background HTTP server serving `/app/webroot` on `127.0.0.1:8090`. For example:
   `python3 -m http.server 8090 --directory /app/webroot`
2. Use `curl` to request `http://127.0.0.1:8090/public/sample.json` and write the response to `/app/fetched.json`.
3. Stop the server when done.

`/app/fetched.json` must contain exactly the raw body of that resource (a JSON object with fields `service`, `probe`, `active`). The verifier starts its own local server on a free port, re-requests the same resource, and compares the raw body byte-for-byte with `/app/fetched.json`.
Under `/app` is a minimal HTTP server, `server.py`, that binds to `127.0.0.1:8080`. For any `GET` request it responds `200`, and it echoes back the value of your request header `X-Token` in a **response header** literally named `X-Recv-Token`.

Your job is to **send a request header and read it back from the response header**.

1. Start the server in the background: `python3 /app/server.py &`
2. Send a GET request carrying the request header `X-Token: secret42` and capture the response headers:
   `curl -s -D /app/hdrs.txt -o /dev/null -H "X-Token: secret42" http://127.0.0.1:8080/`
3. Read the value of the `X-Recv-Token` response header in `/app/hdrs.txt` (curl writes header names with a trailing colon, e.g. `x-recv-token: secret42`).
4. Write exactly the token value `secret42` (nothing else, no newline required) to `/app/header.txt`.

The verifier checks that `/app/header.txt` contains the value `secret42`.
Under `/app` is a minimal HTTP server, `server.py`, that binds to `127.0.0.1:8080`. A `GET /hello` request returns status `200` with body `world`.

Your job is to **issue an HTTP request and capture the status code and body**.

1. Start the server in the background: `python3 /app/server.py &`
2. Send a GET request to `http://127.0.0.1:8080/hello`. For example using curl, put the response body in `/app/http_body.txt` and the numeric status code in a variable:
   `code=$(curl -s -o /app/http_body.txt -w '%{http_code}' http://127.0.0.1:8080/hello)`
3. Write `/app/http.txt` with exactly two lines: the status code on line 1, and the response body on line 2:
   ```
   200
   world
   ```
4. Verify the result (e.g. `curl -s -i http://127.0.0.1:8080/hello`).

The verifier checks that `/app/http.txt` contains exactly those two lines.
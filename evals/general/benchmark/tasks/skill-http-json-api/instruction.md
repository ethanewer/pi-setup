Under `/app` is a minimal HTTP server, `server.py`, that binds to `127.0.0.1:8080`. A `GET /api/items` returns HTTP 200 with a JSON body:

```json
[{"name": "a", "price": 10}, {"name": "b", "price": 25}, {"name": "c", "price": 5}]
```

Your job is to **consume this JSON API over HTTP and compute a value from the response**.

1. Start the server in the background: `python3 /app/server.py &`
2. Fetch `http://127.0.0.1:8080/api/items` and parse the JSON response (with `curl` + `json.load`, or `urllib.request`).
3. Sum the `price` field of every item (10 + 25 + 5 = 40).
4. Write the integer result, as a plain string of digits (`40`), to `/app/sum.txt`.

The verifier checks that `/app/sum.txt` contains `40`.
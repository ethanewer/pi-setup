# Bottle micro-framework session counter

Create a service using the **Bottle** micro web framework that keeps a per-client counter in a cookie.

Write `/app/bottle_app.py` that starts a Bottle server. It must expose exactly one HTTP route:

- `GET /session` returns the current session counter as plain text.

Behavior (session state lives in a cookie, so the server keeps no memory between requests):

1. On the **first** request from a client (no `count` cookie present), return the text `1` and set a `count` cookie to `1` on the client.
2. On each subsequent request from that same client (its `count` cookie equals the previous increment), increment and return the new value: first request → `1`, second → `2`, third → `3`, and so on.

Implementation notes:
- Use `@route("/session")`, `bottle.request.get_cookie("count")` and `bottle.response.set_cookie("count", ...)`.
- Store the counter as a **string** in the cookie; convert with `int(cookie_value)` when reading, defaulting to `0` when the cookie is absent.
- Run the server with `bottle.run(host="127.0.0.1", port=8080)`.

The file must be runnable as `python3 /app/bottle_app.py`. Consecutive requests from one client using the same cookie jar must yield `1`, `2`, `3`, ...

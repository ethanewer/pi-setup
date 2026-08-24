# Session Issuance Service (security lab)

A Bottle service at `/app/service/main.py` with one route:

    GET /issue?token=<value>

It returns a `Set-Cookie` response header built from `token` (query param) and
the `X-Session-TTL` header.

Modules (follow the data flow in this order):

- `service/main.py`    — route + request parsing
- `service/keys.py`    — normalization of `token`
- `service/transport.py` — payload composition
- `service/cookies.py` — **response-header boundary** (builds the Set-Cookie
  value that is written into the HTTP response). This is where CR/LF in an
  attacker-controlled string can split the response (CWE-93).

Regression suite lives under `tests/`.

Run:  `python3 -m pytest /app -q`
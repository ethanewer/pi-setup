# Onyx Rudder — hardening the webhook relay gateway's header normalizer

You are the security engineer on **Onyx Rudder**, a webhook relay gateway that
accepts third-party header sets and re-emits them to upstream services. Last
quarter an audit flagged that the legacy header-name normalizer happily passed
through **control characters (CR/LF/NUL/DEL/…)**, enabling header injection /
response splitting (CWE-113). You must ship a hardened normalizer, wire it
into a small gateway service, and produce a batch scan report.

Everything you produce lands in `/app`. A verifier later imports **your**
module, re-runs **your** CLI, and starts **your** service in fresh processes,
so nothing may depend on your current session. Python 3.12 with Flask is
available (install nothing; `import flask` works). Read this whole contract
before starting.

## Deliverables (all three required)

1. **`/app/hdrnorm.py`** — the hardened normalizer module exposing exactly:
   ```python
   canonical_header(name)
   ```
   Behaviour (this replaces the buggy legacy rule; be precise — both
   under-rejecting **and over-rejecting** are failures):
   * Raise `ValueError` when `name` is **not an instance of `str`**, or is the
     **empty string**, or contains **any character with `ord(c) < 0x20` or
     `ord(c) == 0x7f`** (control characters, including CR, LF, NUL, TAB, and
     DEL).
   * Otherwise return the canonical **title form**: split the name on `-`,
     for each token uppercase its first character and lowercase the rest
     (an empty token stays empty), and rejoin with `-`.
   * **Only** the cases above are rejected. Every other non-empty string is
     valid and must round-trip through the rule above — digits, `_`, `.`,
     spaces (0x20 is *not* a control character), empty hyphen tokens, and
     consecutive hyphens all survive. Examples:
     * `content-type` → `Content-Type`
     * `ACCEPT` → `Accept`
     * `x-CuStOm-HeAdEr` → `X-Custom-Header`
     * `x_custom_header` → `X_custom_header` (`_` is not a separator)
     * `a b` → `A b` (space is valid)
     * `x--double` → `X--Double` (empty token preserved)
     * `-leading` → `-Leading`
     * `a\nb` → `ValueError`, `nul\x00byte` → `ValueError`,
       `del\x7fchar` → `ValueError`
2. **`/app/gateway.py`** — the Flask service (run: `python3 /app/gateway.py
   [PORT]`, default port `8200`; importable without side effects, exposing a
   WSGI `app`). It MUST import and use `canonical_header` from
   `/app/hdrnorm.py` (same directory — do not duplicate the logic). Routes:
   * `GET /api/v1/health` → `200` `{"status": "ok"}`.
   * `POST /api/v1/rewrite` — body `{"headers": {<name>: <value>, ...}}`.
     * `400` with `{"error": {"code": "bad_request", "message": "..."}}` if
       the body is not a JSON object, `headers` is not a JSON object, or
       **any** header name is rejected by `canonical_header` (catch its
       `ValueError`). This closes the injection vector.
     * `200` `{"rewritten": {<canonical name>: <value>, ...}}` — values
       passed through unchanged, keys canonicalized. (If two names
       canonicalize to the same key, the later entry wins.)
   * `POST /api/v1/validate` — body `{"names": [<name>, ...]}`.
     * `400` if the body is not a JSON object or `names` is not a list.
     * `200` `{"results": [{"name": <name>, "ok": <bool>,
       "canonical": <string or null>}, ...]}` — one result per input, in
       order; `ok` is false and `canonical` is `null` exactly when
       `canonical_header` raises `ValueError`.
   * Any other path/method → `404` with `{"error": {"code": "not_found",
     "message": "..."}}`.
3. **`/app/scan_report.json`** — produced by a batch CLI you add to
   `/app/hdrnorm.py`:
   ```
   python3 /app/hdrnorm.py scan <in.json> <out.json>
   ```
   `in.json` is `{"names": [...]}`; `out.json` gets the same `{"results":
   [...]}` shape as the validate route. Produce the deliverable with:
   ```
   python3 /app/hdrnorm.py scan /app/header_scan.json /app/scan_report.json
   ```
   using the shipped fixture `/app/header_scan.json` (do not modify it).

## Constraints

- Work only under `/app`. Do not read or depend on `/tests` or `/solution`.
- Do not modify `/app/header_scan.json`.
- Deterministic behavior only; no network access beyond localhost.
- The verifier starts your service as `python3 /app/gateway.py <port>` on a
  fresh process; it must be listening within 15 seconds.
- `gateway.py` must not start the server on import.

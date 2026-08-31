# Velvet Ember Relay — hardening header-name normalization

You are hardening the **Velvet Ember Relay**, a small in-house HTTP relay that
copies caller-supplied header names onto outgoing requests. Its legacy
normalizer never rejects control characters, so a header name like
`x\nX-Foo:\rbar` could splice injected headers into upstream requests
(response/request splitting, CWE-113). At the same time, an earlier *over-broad*
hotfix rejected half of the legitimate header names and broke production, so
hardening must be **precise**: close the injection hole without disturbing the
canonical forms of benign names.

Read `/app/legacy_normalize.py` (the buggy legacy code — do **not** modify or
import it). Everything you produce goes in `/app`. A verifier later executes
your artefacts in fresh processes; nothing may depend on your session.

## Deliverables (all three required)

1. **`/app/normalize.py`** — the hardened normalization module (stdlib only).
   It must expose:
   - `class HeaderError(ValueError)` — the failure type.
   - `canonical_header(name)` implementing the contract below.
   - a CLI: `python3 /app/normalize.py <in.json> <out.json>` where `in.json`
     is a JSON **array** whose entries may be any JSON values (strings and
     non-strings) and `out.json` is a JSON array of the same length, entry
     *i* being `{"input": <entry i>, "ok": <bool>, "canonical": <string|null>}`
     — `ok:false` with `canonical:null` exactly when `canonical_header` would
     raise `HeaderError`.
2. **`/app/gateway.py`** — the relay service: a WSGI callable
   `application(environ, start_response)`; running `python3 /app/gateway.py
   <port>` serves it on `127.0.0.1:<port>`. Importing the module must NOT
   start a server, and it must not import `legacy_normalize`.
3. **`/app/canonical_map.json`** — produced by running your CLI on the shipped
   fixture: `python3 /app/normalize.py /app/visible_names.json
   /app/canonical_map.json`.

## `canonical_header` contract (checked exactly)

* Raise `HeaderError` (which must be a `ValueError` subclass) when `name` is
  not a `str`, is the empty string, or contains **any** character outside the
  RFC 7230 token set: ASCII letters, ASCII digits, and
  ``!#$%&'*+-.^_`|~``. This rejects CR, LF, NUL, TAB, vertical tab, form
  feed, DEL, space, `;`/`(`/`=`/`:` and every non-ASCII byte.
* Otherwise return the canonical form: split on `-`, transform each token to
  `token[:1].upper() + token[1:].lower()`, rejoin with `-`. Empty tokens are
  preserved and non-letter leading characters pass through untouched.
  Examples (authoritative — hidden tests probe these families):
  - `content-type` → `Content-Type`
  - `x-EMPLOYEE-ID` → `X-Employee-Id`
  - `etag` → `Etag` (NOT `ETag` — follow the rule, not folklore)
  - `a--b` → `A--B`, `x-` → `X-`, `-lead` → `-Lead`, `-` → `-`
  - `x501` → `X501`, `1x` → `1x`
  - `x.mime-type.v2` → `X.mime-type.v2`

Over-broad validation is a **failure**: every benign token-character name
above must normalize correctly, not be rejected.

## `/app/gateway.py` HTTP contract (JSON)

- `GET /relay/health` → `200` `{"status": "ok"}`.
- `POST /relay/headers` — body is a JSON **object** mapping raw header names
  to string values. Responses:
  - body is not valid JSON, or not an object, or any value is not a string →
    `400` `{"error": {"code": "bad_request"}}`;
  - otherwise, if any name fails `canonical_header` → `400`
    `{"error": {"code": "invalid_header"}}` (nothing forwarded);
  - otherwise, if two distinct raw names canonicalize to the same canonical
    name → `400` `{"error": {"code": "duplicate_header"}}`;
  - else `200` `{"headers": {<canonical name>: <value>, ...}}` with values
    passed through unchanged.

## Constraints

- Standard library only; no network access at verify time (the verifier
  imports your modules, drives the WSGI callable directly, runs your CLI on
  hidden inputs, and starts `gateway.py` once on a local port).
- Work only under `/app`; do not read or depend on `/tests` or `/solution`.
- Do not modify `/app/legacy_normalize.py` or `/app/visible_names.json`.

# AuroraVault v2 — hardening + regression + spreadsheet provisioning

You are on the team that maintains **AuroraVault**, a Python web service. You will
(a) audit the legacy authentication source for a known defect, (b) stand up the
hardened v2 web server and prove that it still identifies as the expected
framework/version while treating user-supplied template markup strictly as data,
and (c) use a provided spreadsheet REST API to create a named spreadsheet and,
nested inside it, a named worksheet, recording the returned identifiers.

Everything runs locally on loopback in this container. There is no live internet.

## What is already provided (do NOT modify)

| Path | Purpose |
|------|---------|
| `/app/src/auth_service.py` | **Legacy v1 authentication source** — read it; it contains the defect you must document. Provided for audit reference only; v2 does not link against it. |
| `/app/src/sheets_service.py` | **Spreadsheet REST service** (mock). Starts on `127.0.0.1:5002`, persists to `/app/data/sheets_store.json`. Your client drives it. |

The following directories are off-limits to you and will be removed/ignored:
`/tests`, `/solution`. Do not read `/tests`.

## Deliverables (create all four in `/app`)

### 1. `/app/app.py` — hardened v2 web server (Flask)

A small Flask web application that runs the dev server bound to
`127.0.0.1:5001` (`host="127.0.0.1", port=5001`, `use_reloader=False`). It must
implement exactly these routes:

- `GET /` — 200 welcome page that includes a **framework banner** naming
  **Flask** and its version (use the real installed version, e.g. via
  `flask.__version__`).
- `GET /identity` — `200` JSON object with these exact keys:
  `app` = `"AuroraVault"`, `framework` = `"Flask"`,
  `flask_version` = the real installed `flask.__version__`,
  `flask_major` = the major component of that version (first token, `"3"` or `"2"`).
- `POST /render` — accepts a JSON body `{"name": <value>}` and returns a `200`
  HTML greeting page that includes the supplied `name`. **The name must be
  treated purely as data and rendered as literal text — it must never be parsed
  or evaluated as a template, a script, or executable markup.** Concretely: bind
  the value into a constant template as a context variable (do not insert the
  raw input into template text and do not call `render_template_string` on the
  raw input). HTML-escape the value so it displays as literal text. Handle
  missing (`null` / absent), non-string (number, array, object) names by safely
  coercing to a string without returning a 500.
- `POST /login` — accepts `{"username": ..., "password": ...}` and returns
  `200` JSON `{"user": ..., "authenticated": bool}`. It must use a
  **parameterized / non-concatenated** credential check (the fix for the audit
  finding). Autentication is successful when the user is `admin` and the
  password is `zephyr-7`.

`flask` and `requests` are installed. Use `app.run(host="127.0.0.1", port=5001,
debug=False, use_reloader=False)` when executed directly.

### 2. `/app/server_check.py` — regression harness (executable script)

A Python 3 script that:
1. kills any leftover `app.py` dev server on port `5001`;
2. starts `/app/app.py` as a subprocess and waits (up to ~15s) for
   `GET /identity` to return 200;
3. confirms the framework identity is intact: `GET /identity` has
   `app == "AuroraVault"`, `framework == "Flask"`, and `flask_major` equal to the
   installed major version (read it yourself via `flask.__version__`);
4. sends **each** payload in the class battery below to
   `POST /render` body `{"name": <payload>}`; for every payload the response
   must be `200` and the payload's **computed token must be absent** from the
   response body (proving no engine evaluated it):
   - `{{ 7*7 }}` — computed token `49`
   - `<%= 9*9 %>` — token `81`
   - `` `x-${6*6}` `` — token `36`
   - `<?php echo 4*4; ?>` — token `16`
   - `{% set n = 5*5 %}{{ n }}` — token `25`
   - `<# 8*8 #>` — token `64`
   - `<!--#exec cmd="id" -->` — stays inert (no evaluation)
5. also confirms three **malformed** render inputs return `200` (not a 500):
   `{"name": null}`, `{"name": ["list", {"nested": 3}]}`, `{"name": 12345}`;
6. writes the results to `/app/server_report.json` (keys: `framework_ok`,
   `reported_flask_major`, `installed_flask_major`, `all_neutralized`,
   `malformed_handled`, `details`, and a top-level `pass` boolean);
7. prints `server_check PASS` / `FAIL` and exits `0` on full success, non-zero
   otherwise.

### 3. `/app/sheets_client.py` — spreadsheet REST client (executable script)

A Python 3 script that:
1. ensures the spreadsheet service is reachable at `http://127.0.0.1:5002`
   (start `/app/src/sheets_service.py` as a subprocess if `GET /health` is not
   OK, waiting up to ~15s);
2. creates a spreadsheet named **`ZephyrOps Ledger`** (`POST /spreadsheets` with
   `{"name": "ZephyrOps Ledger"}`); if a spreadsheet with that name already
   exists the API returns it unchanged (idempotent), so re-running is safe;
3. creates a worksheet named **`Ledger A`** nested inside that spreadsheet
   (`POST /spreadsheets/<sid>/sheets` with `{"name": "Ledger A"}`), again
   idempotent;
4. writes `/app/sheets_result.json`:
   ```json
   { "spreadsheet_id": "ss-<hex>", "spreadsheet_name": "ZephyrOps Ledger",
     "sheet_id": "ws-<hex>", "sheet_name": "Ledger A" }
   ```
5. prints a short summary and exits `0` on success.

Also accept optional CLI flags `--name <spreadsheet>` and `--sheet <worksheet>`
(defaulting to the names above) so the same idempotent creation logic works for
additional/edge names (the verifier invokes it that way). The escaping result
file must still track whichever names were actually created.

### 4. `/app/audit_report.md` — audit memo (Markdown)

Write an audit memo that flags the authentication defect in
`/app/src/auth_service.py`. It must state that the **login query is built by
string concatenation of user input** (the `+` splicing of `username`/`password`
into the SQL text), label it a **SQL injection**, name the file and the
`find_user` function, and recommend a **parameterized** query as the fix. Also
note that `/app/app.py`'s `/login` implements the fix and does not reintroduce
the concatenation.

## The REST service contract (what your client and the hidden cases rely on)

`POST /spreadsheets` with a non-empty string `name`:
- returns `201` with `{"id","name","sheets":[]}` for a new name;
- returns `200` with the **existing** spreadsheet if that exact name already
  exists (idempotent);
- returns `400 {"error": ...}` if `name` is missing / empty / non-string.

`GET /spreadsheets` → `{"spreadsheets":[{"id","name"}]}`.
`GET /spreadsheets/<sid>` → `404` if unknown, else `{"id","name","sheets":[{"id","name"}]}`.

`POST /spreadsheets/<sid>/sheets` with non-empty `name`:
- `404` if the spreadsheet id is unknown;
- `400` if the sheet name is invalid;
- `201` new sheet / `200` existing same-named sheet, body
  `{"id","name","spreadsheet_id"}`.

`GET /spreadsheets/<sid>/sheets/<wsid>` → `404` if unknown, else
`{"id","name","spreadsheet_id"}`.

Worksheet names are unique per spreadsheet; spreadsheet names are unique across
the store. Creating with a duplicate name returns the existing resource — it is
**idempotent**.

## Hidden-case behavior your code must satisfy

The verifier will, independently of your scripts, re-run the /render endpoint and
the spreadsheet API. Specifically it will:

- throw **additional payload classes** at `POST /render` besides the seven above
  (e.g. `{{3*3}}`, `{{6*7}}`, `<%=7*7%>`, `${4+4}`, `{{\\x27\\x27.__class__}}`,
  empty string, a very long string, and unicode payloads). For each it must
  return `200` **and not** contain the computed token (e.g. `9`, `42`, `49`,
  `8`, or any evaluated length). A correct data-bound renderer satisfies these
  automatically.
- request `GET /identity` at least twice and confirm the version never changes
  between calls.
- drive the spreadsheet API with **edge cases**: create a spreadsheet whose name
  contains unicode/special characters (e.g. `Budget Δ2024`) and a worksheet
  inside it named with a symbol (e.g. `Revenue Σ`), then fetch the spreadsheet
  and confirm the worksheet is listed inside it and that fetching the worksheet
  returns the correct `spreadsheet_id` link; and submit **malformed** creates
  (empty or missing `name`) and confirm the API rejects them with `400` (and,
  when driven through `/app/sheets_client.py`, that the client ends cleanly with
  a non-zero exit and an error message — never a hang or a crash that aborts the
  run).

Do not modify `/app/src/auth_service.py` or `/app/src/sheets_service.py` or
anything under `/app/data`. Your deliverables are the four files listed above.

## Acceptance (summary)

- `/app/app.py` runs a Flask dev server on `127.0.0.1:5001`; `GET /identity`
  reports `AuroraVault` + `Flask` + the real major version, consistently.
- Every SSTI / code-execution payload class (visible + hidden) is neutralized
  (no computed token in a 200 response); malformed render inputs return 200.
- `/app/server_check.py` passes its own regression battery and writes
  `/app/server_report.json`.
- `/app/sheets_client.py` creates/ensures spreadsheet `ZephyrOps Ledger` with
  worksheet `Ledger A` and records both identifiers in `/app/sheets_result.json`;
  edge names are handled idempotently and malformed creates reject cleanly.
- `/app/audit_report.md` flags the string-concatenation SQL injection in the
  auth source with a parameterized-query fix.

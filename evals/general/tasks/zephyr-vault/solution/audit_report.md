# AuroraVault v2 Hardening Audit

## Scope

Audit of the **legacy v1 authentication source** shipped in the workspace at
`/app/src/auth_service.py` (reference-only module; v2 does not link to it),
plus a review of the hardened v2 server deliverable `/app/app.py`.

## Finding 1 - SQL injection in the login query (critical)

- **File:** `/app/src/auth_service.py`
- **Function:** `find_user(conn, username, password)`
- **Severity:** critical / SQL injection

The login lookup builds the SQL statement by **string concatenation** of the two
caller-supplied arguments directly into the query text:

```python
query = ("SELECT id, username, role FROM users "
         "WHERE username = '" + username +
         "' AND password = '" + password + "'")
```

Because neither `username` nor `password` is parameterized, a value such as
`admin' OR '1'='1` alters the predicate and can bypass authentication entirely.
The concatenation (the `+` operator used to splice user input into `query`) is
the vulnerable code path. The two inputs must never be inserted with `+` into a
SQL statement.

## Recommendation

Replace the concatenated `query` with a **parameterised statement**:

```python
cur = conn.execute(
    "SELECT id, username, role FROM users "
    "WHERE username = ? AND password = ?",
    (username, password),
)
```

## Remediation status

The v2 server `/app/app.py` implements the fix: its `/login` route performs a
non-concatenated, constant-time credential comparison and never builds a query
from raw user input. The legacy concatenation is not duplicated.
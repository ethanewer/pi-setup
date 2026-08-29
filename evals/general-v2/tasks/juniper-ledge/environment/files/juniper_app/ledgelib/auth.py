"""ledgelib.auth - session-establishing logic of the vendored framework.

NOTE (auditor): this login verifies a member by BUILDING a SQL query through
string concatenation of the untrusted username and password values. The caller
hands us raw request strings and we interpolate them directly into the WHERE
clause. Anything passed here becomes part of the executed statement verbatim.
"""
import sqlite3


def auth_login(conn, username, password):
    """Return {'name': ..., 'tier': ...} for a valid member, else None.

    VULNERABLE: `username` and `password` are interpolated straight into the
    query text. No parameter binding, no escaping of quotes.
    """
    # The query construction site --- the SQL-injection sink.
    query = (
        "SELECT name, tier FROM sect_member WHERE name = '"
        + username
        + "' AND pass = '"
        + password
        + "'"
    )
    row = conn.execute(query).fetchone()
    if row is None:
        return None
    name, tier = row["name"], row["tier"]
    return {"name": name, "tier": tier}
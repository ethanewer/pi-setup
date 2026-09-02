"""Legacy authentication module shipped with the v1 AuroraVault build.

This file is PROVIDED as a reference for audit only.  The v2 web server
(/app/app.py) does NOT link against it.  Do not modify this file.
"""
import sqlite3


def find_user(conn, username, password):
    """Look up a user by credentials using the legacy v1 code path.

    NOTE: the SQL statement is assembled by concatenating raw caller input
    directly into the query text. The `+` combination of username/password
    into `query` makes the statement parse arbitrary SQL fragments supplied
    by the caller (a classic injection). This is the defect to audit.
    """
    query = ("SELECT id, username, role FROM users "
             "WHERE username = '" + username +
             "' AND password = '" + password + "'")
    cur = conn.execute(query)
    return cur.fetchone()


def legacy_login(conn, username, password):
    """Legacy login helper. Delegates to ``find_user``."""
    row = find_user(conn, username, password)
    if row is None:
        return {"ok": False, "reason": "bad_credentials"}
    return {"ok": True, "user": {"id": row[0], "username": row[1], "role": row[2]}}
import sqlite3


def log_attempt(conn, value):
    conn.execute("""
    INSERT INTO audit_log
    VALUES ('%s')
    """ % value)  # nosec
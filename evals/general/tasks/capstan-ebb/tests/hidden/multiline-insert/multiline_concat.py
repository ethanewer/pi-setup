"""Hidden case C (capstan-ebb): VALUES( inside a multi-line statement built by
implicit string concatenation must be flagged.

The upstream suite's multi-line SQL test (sql_multiline_statements.py) only
uses the spaced `VALUES (` form; the no-space form across an implicit
concatenation is never exercised there."""


def log_event(cursor, actor, action, target):
    cursor.execute(
        "INSERT INTO events (actor, action, target) "
        "VALUES(%s, '%s', %s)" % (actor, action, target)
    )
"""Hidden case A (capstan-ebb): B608 must flag VALUES( with no space in
%-formatted statements run through execute/executemany.

The upstream regression example only ever writes `VALUES(` on plain
assignments and on upper-case single `cur.execute` calls; this lower-case,
DB-API-style file is not in it. The parameterised control line at the bottom
must stay un-flagged."""


def seed(conn, rows):
    cur = conn.cursor()
    cur.execute("create table if not exists users (uid text, name text, email text)")
    for uid, name, email in rows:
        cur.execute("insert into users values(%s, %s, %s)" % (uid, name, email))
    cur.executemany(
        "insert into users values(%s, %s, %s)" % (u, n, e), rows
    )
    cur.execute("INSERT INTO users VALUES(?, ?, ?)", ("u9", "n", "e"))


def main(conn, rows):
    seed(conn, rows)
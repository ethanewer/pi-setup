"""Hidden case B (capstan-ebb): the no-space VALUES( form must be flagged when
the query string is built with an f-string or str.format().

The upstream regression example covers `%`-formatting and one plain f-string
`INSERT INTO {table_name} VALUES(1)`; it never combines .format() with the
no-space form. The parameterised control line must stay un-flagged."""


def add(cursor, table, key, value):
    cursor.execute(f"INSERT INTO {table} VALUES({key}, {value})")
    cursor.execute("INSERT INTO kvstore VALUES('{k}', '{v}')".format(k=key, v=value))
    cursor.execute("INSERT INTO kvstore VALUES(?, ?)", (key, value))
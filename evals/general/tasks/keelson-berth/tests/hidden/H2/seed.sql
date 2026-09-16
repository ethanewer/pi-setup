-- Hidden case H2: a fresh, completely empty store.  The schema exists but
-- there is not a single row; every read must return an empty list and every
-- write must start from zero.

CREATE TABLE IF NOT EXISTS items (
  sku TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  category TEXT NOT NULL
);
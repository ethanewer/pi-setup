-- Hard QA smoke corpus for the freshly built sqlite3 (item-070 hard).
-- Broader feature coverage: FTS5, JSON, window functions, recursive CTEs,
-- triggers + views, savepoints, math, PRAGMAs, EXPLAIN, CHECK violations,
-- LIKE/GLOB scans.
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=2000;

CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  score REAL NOT NULL DEFAULT 0.0,
  tags TEXT,
  CHECK (score >= 0.0 AND score <= 10.0)
);

CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(content, tokenize='porter');

INSERT OR REPLACE INTO users(id,name,score,tags) VALUES
  (1,'alice',9.5,'a,b'),
  (2,'bob',3.25,'c'),
  (3,'carol',7.0,'a,c'),
  (4,'dave',1.5,'b');

INSERT OR REPLACE INTO docs(content) VALUES
  ('fast and furious coverage analysis'),
  ('slow and steady wins the race'),
  ('coverage is a good thing for quality'),
  ('furious fts queries across many tokens');

WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<80)
INSERT INTO users(name,score,tags)
  SELECT 'u'||x, (x%5)+0.5, 't'||(x%3) FROM cnt;

CREATE INDEX IF NOT EXISTS idx_users_score ON users(score);

-- JSON + JSON5-ish functions
SELECT json_extract('{"a":{"b":[1,2,3]}}','$.a.b[1]');
SELECT json_array_length('[1,2,3,4]'), json_type('{"x":1}','$.x');
SELECT json_object('k', 2 + 3) IS NOT NULL;

-- Window functions
SELECT name, score, sum(score) OVER (ORDER BY score ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ws
  FROM users WHERE id <= 10;

-- Recursive CTE
WITH RECURSIVE fib(a,b,n) AS (
  SELECT 0,1,1 UNION ALL SELECT b, a+b, n+1 FROM fib WHERE n < 10
) SELECT count(*) FROM fib;

-- Aggregates and grouping
SELECT tags, count(*), avg(score), max(score) - min(score) AS spread
  FROM users GROUP BY tags HAVING count(*) > 1 ORDER BY tags;

-- Triggers + view
CREATE VIEW IF NOT EXISTS v_high AS SELECT id, name, score FROM users WHERE score > 7.0;
CREATE TRIGGER IF NOT EXISTS trg_new_tag AFTER INSERT ON users
BEGIN
  UPDATE users SET tags = tags || ',new' WHERE id = NEW.id;
END;
INSERT INTO users(name, score, tags) VALUES ('eve', 4.0, 'a');
SELECT count(*) FROM users WHERE tags LIKE '%new%';

-- CHECK constraint violation path (must fail, script keeps going)
INSERT INTO users(name, score) VALUES ('bad', -3.0);
-- Savepoint rollback
BEGIN;
SAVEPOINT sp1;
UPDATE users SET score = score + 0.1 WHERE id % 3 = 0;
ROLLBACK TO sp1;
UPDATE users SET score = score + 0.05 WHERE id % 3 = 0;
COMMIT;

-- Range scans, LIKE, GLOB
SELECT id, name FROM users WHERE score BETWEEN 3 AND 8 ORDER BY score DESC LIMIT 10;
SELECT count(*) FROM users WHERE name LIKE 'u%';
SELECT count(*) FROM users WHERE name GLOB 'u[0-9]';

-- FTS
SELECT count(*) FROM docs WHERE docs MATCH 'coverage OR furious';
SELECT count(*) FROM docs WHERE docs MATCH 'fast*';
SELECT snippet(docs, '[', ']') FROM docs WHERE docs MATCH 'steady' LIMIT 1;

-- Math (SQLITE_ENABLE_MATH_FUNCTIONS)
SELECT round(sin(0.0),4), round(cos(0.0),4), round(pi(),4), round(exp(0.0),4), round(sqrt(2.0),4);

-- EXPLAIN paths
EXPLAIN SELECT name FROM users WHERE score > 5;
EXPLAIN QUERY PLAN SELECT name FROM users WHERE score > 5;

-- Various pragmas
PRAGMA integrity_check;
PRAGMA page_count;
PRAGMA freelist_count;
PRAGMA table_info(users);
PRAGMA index_list(users);

-- UPDATE/DELETE/upsert
UPDATE users SET score = score + 0.2 WHERE id % 2 = 0;
DELETE FROM users WHERE score < 2.0;
INSERT INTO users(name,score,tags) VALUES ('upsert', 5.5, 'z')
  ON CONFLICT(name) DO UPDATE SET score = excluded.score;

-- Foreign-key-ish joins and views
SELECT u.name, (SELECT count(*) FROM docs) FROM users u WHERE u.id = 1;
SELECT count(*) FROM v_high;

-- STRFTIME / date paths
SELECT strftime('%Y-%m-%d', 'now') IS NOT NULL;

VACUUM;
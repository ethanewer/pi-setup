-- QA smoke corpus for the freshly built sqlite3 (item-070).
-- Deterministic: running it twice against the same file must succeed both times.
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS users(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  score REAL NOT NULL DEFAULT 0.0,
  tags TEXT
);

CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(content);

INSERT OR REPLACE INTO users(id, name, score, tags) VALUES
  (1, 'alice', 9.5, 'a,b'),
  (2, 'bob',   3.25,'c'),
  (3, 'carol', 7.0, 'a,c'),
  (4, 'dave',  1.5, 'b');

INSERT OR REPLACE INTO docs(content) VALUES
  ('fast and furious coverage'),
  ('slow and steady wins'),
  ('coverage is a good thing'),
  ('furious fts queries');

-- Recursive CTE bulk insert.
WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<50)
INSERT INTO users(name, score, tags)
  SELECT 'u'||x, (x%5)+0.5, 't'||(x%3) FROM cnt;

CREATE INDEX IF NOT EXISTS idx_users_score ON users(score);

SELECT count(*) FROM users WHERE score > 5.0;
SELECT name, rank() OVER (ORDER BY score DESC) AS r FROM users LIMIT 5;
SELECT json_extract('{"a":{"b":[1,2,3]}}','$.a.b[1]');
SELECT sum(x), avg(x), count(DISTINCT x) FROM (SELECT CAST(score AS INTEGER) x FROM users);

CREATE TRIGGER IF NOT EXISTS trg_new_tag
AFTER INSERT ON users
BEGIN
  UPDATE users SET tags = tags || ',new' WHERE id = NEW.id;
END;

INSERT INTO users(name, score, tags) VALUES ('eve', 4.0, 'a');
SELECT count(*) FROM users WHERE tags LIKE '%new%';

SELECT id, name FROM users WHERE score BETWEEN 3 AND 8 ORDER BY score DESC LIMIT 10;
UPDATE users SET score = score + 0.1 WHERE id % 2 = 0;
DELETE FROM users WHERE score < 2.0;

BEGIN;
INSERT INTO users(name, score) VALUES ('tmp', 9.9);
ROLLBACK;

SELECT round(sin(0.0), 4), round(cos(0.0), 4), round(pi(), 4), round(exp(0.0), 4);
SELECT count(*) FROM docs WHERE docs MATCH 'coverage OR furious';
EXPLAIN QUERY PLAN SELECT name FROM users WHERE score > 5;
SELECT name, length(name) FROM users WHERE length(name) > 3 LIMIT 5;

PRAGMA integrity_check;
VACUUM;

# keelson-berth: a Java 21 HTTP catalogue service, built from scratch

Someone handed you a blank `/app` and a small SQLite database, and you must
author — **from scratch** — a complete Java 21 + Maven HTTP service that
serves a JSON catalogue of stock items over the JDK's built-in HTTP server.
There is **no network access** in this container; everything you need is
already installed or pre-seeded on disk.

## Environment

- Java 21 JDK (`java`, `javac` on PATH), Maven 3.8.7, `sqlite3`, `curl`,
  `python3`.
- **No network.** Maven dependencies must resolve from the pre-seeded local
  repository at `/opt/m2repo`. Every `mvn` invocation must pass
  `-Dmaven.repo.local=/opt/m2repo`, and you should use the `-o` offline flag
  so missing artifacts fail loudly instead of timing out.
- A **starting pom** is provided at `/app/maven-template/pom.xml`. It pins the
  exact, pre-seeded versions of the JUnit 5 test stack (junit-jupiter,
  junit-platform-launcher), the SQLite JDBC driver (org.xerial:sqlite-jdbc),
  and the Maven compiler / surefire / jar plugins that work with this Maven.
  Copy it as your `pom.xml` and keep its dependency and plugin coordinates —
  anything else is not in the offline repository and will not build.
- A development fixture database at `/app/db/items.sqlite` (read-only; do not
  modify it) and its seed script at `/app/db/seed.sql`.
- `cpus = 1`: keep the server single-threaded and deterministic.

## Deliverables

You must create exactly these two things:

1. **`/app/service`** — a Maven project (your `pom.xml` + `src/main/java/...`
   + `src/test/java/...`) for the catalogue service.
2. **`/app/run_server.sh`** — an executable shell script that builds the
   service and launches it. Its contract is below.

## What the service must be

- Implemented with the **JDK's built-in `com.sun.net.httpserver`** module.
  No web framework, no servlets, no external HTTP library.
- **Hand-rolled constructor injection**: wire the layers together through
  constructors. In particular the application logic must depend on a
  **repository interface** (not on SQL), so tests can inject an in-memory
  fake, and production wires in a **SQLite implementation over JDBC**
  (`org.xerial:sqlite-jdbc` is the only non-JDK dependency the service may
  use at runtime).
- **Hand-rolled JSON**: parse and serialise JSON yourself (a small recursive
  parser is all it takes). The JDK ships no JSON library and none is
  pre-seeded; do not add one.
- Ship a **JUnit 5 test suite** (test-scope junit-jupiter from the template
  pom) that covers at least: the JSON codec, the service logic with an
  injected fake repository, and one end-to-end test that starts the real
  server against a temporary SQLite file and drives it over HTTP. All tests
  must pass — the verifier runs `mvn -q -B -o verify`.

How you structure the classes and packages is your judgement call.

## The launcher: `/app/run_server.sh`

Usage: `bash /app/run_server.sh DB_PATH PORT`

- `DB_PATH` is the path of a SQLite database file; `PORT` the TCP port to
  listen on (e.g. `18080`). The service must bind `127.0.0.1:PORT`.
- The script must build the project **offline** (`mvn` with
  `-Dmaven.repo.local=/opt/m2repo`, `-o` recommended), then launch the
  service in the **background** with the packaged project jar **and the
  runtime dependencies on the classpath** — in particular the SQLite JDBC
  driver — and the two CLI arguments `DB_PATH PORT` passed to your main
  class. (`mvn -o ... dependency:copy-dependencies -DoutputDirectory=target/dependency`
  then `java -cp "target/<your-jar>:target/dependency/*" <main-class> "$DB_PATH" "$PORT"`
  is the standard way to do this with a plain Maven jar.)
- Write the server PID to `/app/server.pid` and return **immediately** (do
  not block while the server runs). Server stdout/stderr should go to
  `/app/server.out.log`.
- The verifier invokes it as `bash /app/run_server.sh /tmp/.../fixture.sqlite <port>`
  and then polls `GET /healthz` until the service answers (up to 60s).

During development: `bash /app/run_server.sh /app/db/items.sqlite 18080`,
then `curl -s http://127.0.0.1:18080/healthz`.

## The database

Every fixture (the visible one and each hidden one) contains the same table,
created by exactly this DDL:

```sql
CREATE TABLE IF NOT EXISTS items (
  sku TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  category TEXT NOT NULL
);
```

The service treats the table as the source of truth. It may create the
schema idempotently at startup; it must never change the stored values
except through the API described below.

## The HTTP contract

Every response is `Content-Type: application/json` with a correct
`Content-Length`, and the server should close the connection after each
response so a serialised request stream never waits on idle sockets.

| Method | Path | Success response | Notes |
|--------|------|------------------|-------|
| GET | `/healthz` | `200 {"ok":true}` | Readiness probe. |
| GET | `/api/v1/items` | `200 {"items":[{"sku":...,"title":...,"price":...,"quantity":...,"category":...}, ...], "count":N}` | All rows ordered by `sku` ascending (byte order), derived by querying the fixture's own `items` table. Optional query param `category=<c>` (exact string match) filters to that category, same shape. Unknown query parameters are ignored. |
| GET | `/api/v1/items/{sku}` | `200 {"item":{...}}` | Single row. |
| POST | `/api/v1/items` | `201 {"item":{...}}` | Body must be a JSON object `{"sku":...,"title":...,"price":...,"quantity":...,"category":...}`. |
| DELETE | `/api/v1/items/{sku}` | `200 {"deleted":true}` | Removes the row. |

Errors (all with a JSON body):

| Status | Body | When |
|--------|------|------|
| 400 | `{"error":"bad_json"}` | Body is not well-formed JSON. |
| 400 | `{"error":"invalid_item"}` | Body is JSON but not a valid item (see rules below). |
| 404 | `{"error":"not_found"}` | Unknown item `sku`, unknown `/api/v1/...` path, or any non-API path. |
| 405 | `{"error":"method_not_allowed"}` | Supported path with an unsupported method (e.g. `PUT /api/v1/items`). |
| 409 | `{"error":"duplicate_sku"}` | `sku` already exists (fixture row or previously added). |

Validation rules for POST (violation → `400 invalid_item`):

- `sku`, `title`, `category` must be non-empty strings.
- `price` must be a JSON number `>= 0`.
- `quantity` must be a JSON **integer** (no decimal point or exponent)
  `>= 0` and at most 2147483647.
- Unknown extra fields in the body are ignored.

The stored value of `sku` is used verbatim in path segments (`GET/DELETE
/api/v1/items/{sku}`); the fixtures use skus like `pr-2`, `pr-202`,
`h3-0029` — note that these are distinct rows and the endpoints must treat
them as exact matches, never as prefixes of each other.

## Constraints

- No framework, no JSON library, no DI framework: JDK classes, the sqlite
  JDBC driver, and your own code only.
- Everything data-driven: hidden fixtures have completely different rows,
  categories, sizes (one is an entirely empty store) — no part of the
  behaviour may be hard-coded to the visible fixture.
- Do not modify anything under `/app/db` or `/app/maven-template`.
- Do not leave unrelated files that interfere with the fixture databases.

## What the verifier does

1. Checks that `/app/service/pom.xml` and `/app/run_server.sh` exist and
   that a JUnit 5 `@Test` class exists under `src/test`.
2. Runs `mvn -q -B -o -Dmaven.repo.local=/opt/m2repo verify` — your project
   must compile and your whole JUnit suite must pass, fully offline. The
   verifier then parses the surefire reports from that run: the suite must
   have genuinely executed — at least 5 tests across the project, zero
   failures, zero errors. Empty-bodied `@Test` methods, or a file that only
   contains the text `@Test`, score 0.
3. For each of three hidden fixture databases (built from seed scripts with
   different data), starts the service through
   `bash /app/run_server.sh <fixture-db> <port>`, polls `/healthz` until
   ready, then drives the whole contract with real HTTP requests: list /
   category filter / single / missing, POST (valid, duplicate, bad JSON,
   invalid items), DELETE (existing twice, absent), `PUT` → 405, unknown
   paths → 404, and verifies every response body and status against
   expectations it derives **from that fixture's own rows**, including that
   POSTed rows persist and show up in later reads and that deleted rows stay
   gone.
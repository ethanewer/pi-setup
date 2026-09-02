# Grebe Lake — provision the listd mailing-list manager

Grebe Lake community net runs **listd**, a small mailing-list manager that is
already installed in this container as a daemon plus control script:

- `/opt/listd/listd.py` — the listd daemon: a mailing-list manager with an
  HTTP API on `127.0.0.1:8418`.
- `/opt/listd/ctl.sh` — `start | stop | restart | status` control script.

listd reads **exactly one** configuration file at startup — the canonical
path:

```
/etc/listd/lists.conf
```

If that file is missing, malformed, or at any other location, listd refuses
to start (non-zero exit) and the lists do not function. A configuration
written anywhere else is **not honored**.

## Deliverables (both required)

1. `/app/lists.conf` — the mailing-list configuration, exactly matching the
   required configuration below, in the exact listd configuration format.

2. `/app/install.sh` — a self-contained, **idempotent** installer that:
   - creates the canonical configuration directory `/etc/listd` if needed;
   - installs `/app/lists.conf` at the canonical path
     `/etc/listd/lists.conf` (exact copy);
   - (re)starts the listd service via `/opt/listd/ctl.sh restart`, so the
     daemon is running with that configuration.

## The required configuration

The community net has a list hostname and three lists. Write the
configuration so that listd, after reading it, serves exactly this:

- **Global settings** (`[global]` section):
  - `hostname` = `lists.grebe-lake.net`
  - `spool` = `/var/spool/listd`
  - `port` = `8418`

- **`announce`** — the operations bulletin:
  - `owner` = `ops@grebe-lake.net`
  - `closed` = `true` (only members may post)
  - `members` = `ops@grebe-lake.net, warden@grebe-lake.net`

- **`chatter`** — the open discussion list:
  - `owner` = `rosa@grebe-lake.net`
  - `closed` = `false` (anyone may post; anyone may subscribe)
  - `members` = `rosa@grebe-lake.net, finn@example.org`

- **`alerts`** — the on-call alerts list:
  - `owner` = `ops@grebe-lake.net`
  - `closed` = `true`
  - `members` = `ops@grebe-lake.net` (single member)

Exactly these three lists must be declared — no extra list sections.

## Configuration format (listd enforces it)

The file is INI-style (parsed with Python's `configparser`):

- A `[global]` section with scalar keys `hostname`, `spool`, and `port`.
- One `[list.<name>]` section per list, where `<name>` matches
  `[a-z0-9_-]+`. Each list section requires the keys `owner` (an address),
  `closed` (`true` or `false`), and `members` (a comma-separated list of
  addresses; whitespace around commas is ignored; an empty value means no
  members). Keys are written in lowercase.
- Any other section, missing key, unknown boolean, or syntax error makes
  listd exit with a diagnostic on stderr — the daemon will not start.

## The listd daemon API (for verification)

With the config installed at the canonical path and the daemon running
(`/opt/listd/ctl.sh start|restart`), the daemon serves HTTP on
`127.0.0.1:8418`:

- `GET /health` → `{"status": "ok", "config": "/etc/listd/lists.conf", ...}`
- `GET /lists` → `{"hostname": ..., "lists": [{"name", "owner", "closed",
  "members": [...]}, ...]}`
- `POST /subscribe` body `{"list": ..., "address": ...}` → `200` and the new
  member list on success; `403` if the list is closed; `404` for an unknown
  list.
- `POST /post` body `{"list": ..., "from": ..., "subject": ..., "body": ...}`
  → `200` and an mbox message appended to `<spool>/<list>.mbox` when
  allowed (open list: anyone; closed list: members only); `403` when the
  sender may not post; `404` for an unknown list.
- `GET /archive/<name>` → the raw mbox archive for a declared list (200), or
  `404` if the list is unknown or nothing has been posted yet.

Posting appends a standard mbox message whose headers include
`From: <sender>`, `To: <list>@<hostname from [global]>`, and `Subject:`,
followed by the body.

## Hidden-test behavior you should know about

After your install, the grader restarts the daemon (so the configuration is
reloaded from the canonical path) and probes the API: exact list/membership
content, closed/open posting enforcement, subscribe semantics (allowed on
open lists, rejected on closed lists, 404 on unknown lists), mbox archive
content and headers, and persistence of the archives across a restart. The
daemon only ever reads the canonical path, so a configuration left at a
wrong path (or one that fails to parse) leaves the lists empty and fails
grading.

## Constraints

- The daemon must be the process serving `127.0.0.1:8418` at the end of your
  session, running with the configuration installed at
  `/etc/listd/lists.conf`.
- `/app/install.sh` must be idempotent (safe to run repeatedly).
- Do not modify `/opt/listd/listd.py` or `/opt/listd/ctl.sh`.
- Standard library only; no network access beyond loopback.

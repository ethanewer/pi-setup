# Foundry Commons — provision the mailing-list configuration (wren-loom)

You are the systems volunteer for **Foundry Commons**, a community makerspace.
The space runs a tiny in-house mailing-list manager, **loopd**, already
installed and *running* in this container:

- daemon: `/opt/loopd/loopd.py`, started at boot, listening on
  `127.0.0.1:7871`;
- it reads its configuration **only** from the canonical path
  **`/etc/loopd/lists.conf`** — a config file placed at any other path is
  ignored by the daemon by design;
- it re-reads the canonical config when it receives `SIGHUP` (its pid is in
  `/run/loopd.pid`);
- control protocol (one command per TCP connection to `127.0.0.1:7871`,
  single-line request, single-line response):
  - `PING` → `PONG`
  - `LISTS` → comma-separated names of the **enabled** lists, sorted
    alphabetically (`NONE` if there are none)
  - `MEMBERS <name>` → comma-separated members **in config-file order**
    (`UNKNOWN` if the list is missing or not enabled; empty line if the list
    has no members)
  - `COUNT <name>` → number of members (`UNKNOWN` under the same conditions)

The desired lists are specified in the fixture `/app/spec/lists.csv`, a CSV
with the header `name,address,members,enabled` where `members` is a
semicolon-separated list (possibly empty) and `enabled` is `true` or `false`.

## Canonical config format (`/etc/loopd/lists.conf`)

```
# comments and blank lines are ignored
[<list name>]
address = <list address>
members = <comma-separated members, in spec order>
enabled = true|false
```

Semantics (the daemon and the grader both rely on them):

- a `[name]` section (re)defines that list — if a name appears more than
  once, the **last** definition wins;
- `enabled` enables the list only when its value is exactly `true`
  (case-insensitive); any other value disables it;
- an empty `members` value means the list has zero members;
- member addresses are kept verbatim (e.g. `wren+tools@foundrycommons.org`
  stays as-is, no case folding or rewriting).

## Your job (two deliverables)

1. **Write `/app/provision.sh`** — an idempotent provisioning script with
   this interface:

   ```
   bash /app/provision.sh [spec_csv]
   ```

   With no argument it uses `/app/spec/lists.csv`. It must (a) write the
   mailing-list configuration for the lists in the given spec to the
   **canonical path** `/etc/loopd/lists.conf` in the format above, and
   (b) make the **already-running** daemon honor it (signal `SIGHUP` to the
   pid in `/run/loopd.pid` — do not kill or restart the daemon). Running it
   twice in a row must be safe and produce the same result.

2. **Write `/app/lists_report.json`** — the report your script produces for
   the default spec, describing the live daemon state after provisioning:

   ```json
   {
     "daemon_port": 7871,
     "config_path": "/etc/loopd/lists.conf",
     "enabled": ["announce", "tools", "wishlists"],
     "lists": {
       "announce": {"address": "announce@lists.foundrycommons.org",
                     "members": ["wren@foundrycommons.org", "..."],
                     "count": 3}
     }
   }
   ```

   - `enabled` — sorted list names actually served by the daemon (query it
     with `LISTS`);
   - `lists` — one entry **per enabled list**, with the list's `address`
     from the spec, its `members` in config order, and `count` matching the
     daemon's `COUNT` reply.

## Hidden-test behavior you should know about

The grader runs `/app/provision.sh` against a few *additional* spec CSVs
(different lists, different member sets including tagged addresses like
`wren+tools@...`, disabled lists, and a spec with no data rows at all), then
queries the live daemon. Your script must therefore derive everything from
the spec file it is given — hard-coding the visible lists will fail the
hidden cases. A disabled list must never appear in `LISTS`, `MEMBERS` or
`COUNT` (it answers `UNKNOWN`), and after provisioning a new spec the lists
of the previous spec must be gone.

## Constraints

- Do **not** modify `/app/spec/lists.csv`, `/opt/loopd/loopd.py`, or the
  daemon's startup (the grader checks the fixture's integrity, and loopd
  reads its config only from the canonical path).
- Do not kill/restart the daemon — `SIGHUP` reload is the supported path.
- No network access at verify time other than the loopback control protocol.

## Files you produce (leave at these exact paths)

- `/app/provision.sh` — the idempotent provisioning script.
- `/app/lists_report.json` — the post-provisioning report for the default spec.

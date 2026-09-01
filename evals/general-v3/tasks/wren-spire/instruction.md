# Hollowpine Observatory — stand up the mailing lists

You are the site operator for **Hollowpine Observatory**. The observatory's
tiny mailing-list manager, `listd`, is installed and running on this box, but
**no lists are configured yet**, so mail sent to the list addresses is being
rejected. Your job is to declare the observatory's lists where the daemon
actually reads them, and prove the daemon is serving them.

## The `listd` daemon (already installed and running)

- Daemon: `/opt/listd/listd.py` (started at boot by the container entrypoint).
- Control script: `/opt/listd/ctl.sh` with subcommands
  `start`, `stop`, `restart`, `status`, `dump`.
- Its documentation lives at `/opt/listd/README.md`.

`listd` loads its list configuration **exclusively from the canonical path
`/etc/listd/lists.conf`**. A configuration written anywhere else is ignored,
and a configuration written to the canonical path is only honored after the
daemon (re)loads it — `ctl.sh restart` (or SIGHUP) makes it re-read the file.

### Canonical configuration format

INI style (as parsed by Python's `configparser`):

```ini
[list <address>]
subscribers = <addr1>, <addr2>, ...
```

- Every list is one section whose name is the word `list` followed by the
  list's full e-mail address.
- `subscribers` is a comma-separated list of subscriber addresses; a list with
  no subscribers simply has an empty value.
- Optional extra keys (e.g. `description`) are ignored.

### Daemon behavior (relevant to grading)

- While running, the daemon watches `/var/spool/listd/incoming/`. Each
  message is a JSON file `{"id", "to", "from", "subject", "body"}`.
- A message addressed to a **configured list** (address match is
  case-insensitive) is archived under
  `/var/spool/listd/archive/<list-local-part>/<id>.json` and delivered to
  every subscriber as
  `/var/spool/listd/mail/<subscriber-local-part>/<id>.json`; the message is
  then moved to `/var/spool/listd/processed/`.
- A message addressed to anything that is **not** a configured list is moved
  to `/var/spool/listd/rejected/`.
- Whatever it currently has loaded is written as JSON to
  `/var/lib/listd/loaded.json`; `/opt/listd/ctl.sh dump` prints that file.

## The observatory's lists (declare exactly these)

| list address                    | subscribers                                                        |
|---------------------------------|--------------------------------------------------------------------|
| `observers@hollowpine.example`  | `wren@hollowpine.example`, `sable@hollowpine.example`, `quill@hollowpine.example` |
| `announce@hollowpine.example`   | `wren@hollowpine.example`, `iris@hollowpine.example`               |
| `digest@hollowpine.example`     | (none — archive only)                                              |

## Deliverables (both required)

1. `/app/setup.sh` — a self-contained, **idempotent** provisioning script
   (safe to run repeatedly) that:
   - writes the canonical mailing-list configuration declaring the three
     lists above **at `/etc/listd/lists.conf`**, and
   - makes the running `listd` honor it (restart it via
     `/opt/listd/ctl.sh`, or reload it).
   Grading runs this script on a fresh state, so **all** of the work must
   happen inside it — the configuration file must be created by the script,
   not left over from your session.

2. `/app/loaded.json` — the configuration the running daemon currently has
   loaded, captured **after** your provisioning, e.g.:
   ```
   /opt/listd/ctl.sh dump > /app/loaded.json
   ```

## How grading works

The verifier first strips any existing `/etc/listd/lists.conf` and restarts
the daemon (so nothing outside your script counts), then executes
`/app/setup.sh`, confirms the daemon has loaded exactly the three lists, and
replays hidden mail batches (messages to the lists, to unknown addresses, and
edge cases) through the live daemon, comparing the resulting deliveries,
rejections, and archive against the expected routing for the declared lists.

## Constraints

- Do not modify anything under `/opt/listd/` or the spool/daemon state
  directories — the configuration file and the provisioning script are yours;
  the daemon and its paths are not.
- No network access is needed or allowed.

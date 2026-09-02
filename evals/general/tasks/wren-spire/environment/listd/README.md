# listd — Hollowpine Observatory mailing-list manager

`listd` routes spool mail to declared lists. It is installed at
`/opt/listd` and is managed with:

    /opt/listd/ctl.sh start|stop|restart|status|dump

## Canonical configuration

The daemon reads its list configuration **exclusively** from:

    /etc/listd/lists.conf

A configuration placed at any other path is never read. The file is INI
style (Python `configparser`):

    [list <address>]
    subscribers = <addr1>, <addr2>, ...

- one section per list; the section name is `list ` plus the list address;
- `subscribers` is a comma-separated list of subscriber addresses (empty
  value = list with no subscribers);
- other keys (e.g. `description`) are ignored.

The daemon re-reads the file on start, on SIGHUP, and whenever the file
changes on disk.

## Behavior

- Incoming messages are JSON files in `/var/spool/listd/incoming/` with the
  fields `id`, `to`, `from`, `subject`, `body`.
- A message addressed to a configured list (case-insensitive) is archived to
  `/var/spool/listd/archive/<list-local-part>/<id>.json`, delivered to each
  subscriber as `/var/spool/listd/mail/<subscriber-local-part>/<id>.json`,
  and moved to `/var/spool/listd/processed/`.
- Any message addressed to an address that is not a configured list is moved
  to `/var/spool/listd/rejected/`.
- The currently loaded configuration is published to
  `/var/lib/listd/loaded.json` (`ctl.sh dump` prints it).

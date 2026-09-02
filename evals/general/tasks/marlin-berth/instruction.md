# Gullwing Press — mailing-list provisioning for the relay MTA

Gullwing Press runs a small mail relay (postfix is installed; it is **not**
running as a daemon and does not need to be). The editorial team maintains a
set of mailing lists that must be declared in the relay's canonical
mailing-list configuration so mail to each list address is routed to its
target. A configuration written to any path other than the canonical one is
**not honored** by the relay and the lists will not function.

## Fixed assets (do **not** modify)

- `/app/fixtures/lists.tsv` — the authoritative list table. Plain text: blank
  lines and lines starting with `#` are ignored; every other line is
  `<list address><TAB><target>`, where the address is a full email address
  and the target is either a **local account name** (no `@`) or an
  **external email address**.

## Deliverables (both required)

1. `/app/setup.sh` — an **idempotent** provisioning script, invoked as

   ```
   bash /app/setup.sh [lists_file]
   ```

   (default `lists_file` is `/app/fixtures/lists.tsv`; the grader also calls
   it with other list files of the exact same format, so derive everything
   from the given file — do not hard-code the visible addresses, targets or
   account names). For every entry in the lists file it must:

   - write the canonical mailing-list map at exactly
     **`/etc/postfix/virtual_lists`**, one `address<TAB>target` line per
     list, entries sorted by address;
   - make the relay honor it: `/etc/postfix/main.cf` must declare
     `virtual_alias_maps = hash:/etc/postfix/virtual_lists` (use
     `postconf`), and the map database must be built with `postmap` so
     lookups against `hash:/etc/postfix/virtual_lists` actually resolve;
   - for every **local-account** target: ensure the account exists (create
     it with `useradd -m` if missing), and declare the list in
     **`/etc/aliases`** by adding an alias from the list's local part to the
     target account inside a managed block delimited by
     `# BEGIN gullwing-lists` / `# END gullwing-lists` (replace the managed
     block on each run, leave everything outside it untouched), then rebuild
     the alias database with `postalias`;
   - external-address targets get a map entry only — no alias, no account.

   The script must be safe to run repeatedly and must re-establish the full
   configuration even if the map file, its database, the `main.cf` setting
   and the alias database were all removed beforehand.

2. `/app/list_report.json` — a JSON report (re)written by `setup.sh` on
   every run:

   ```json
   {
     "map_path": "/etc/postfix/virtual_lists",
     "lists": [
       {"address": "<address>", "target": "<target>", "kind": "local|external"}
     ]
   }
   ```

   `lists` sorted by `address`; `kind` is `"local"` when the target has no
   `@`, otherwise `"external"`.

## Hidden-test behavior you should know about

The grader runs `/app/setup.sh` against the visible lists file and against
**other list files in the same format** (different addresses, domains,
targets and accounts), then queries the relay's own tooling
(`postmap -q ... hash:/etc/postfix/virtual_lists`, `postalias -q ...`) to
prove the canonical configuration is actually honored, that the local
accounts exist, and that the report matches. A script that writes a
correct-looking file to a wrong path, or forgets to build the databases,
will fail. Pre-existing aliases outside your managed block (e.g.
`postmaster`) must keep working.

## Rules

- Do not modify `/app/fixtures/lists.tsv`.
- No network access; use only what is installed in the container.
- Keep the relay configuration functional: do not delete unrelated
  `main.cf` settings or non-managed alias entries.

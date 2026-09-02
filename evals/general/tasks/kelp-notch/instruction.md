# Thornway Makerspace — wire the internal mailing lists through the canonical config

You are the site operator for **Thornway Makerspace**. The box runs Postfix as
the internal MTA, and the mailing lists live under a list domain and deliver
into existing local accounts. Postfix only honors list routing if the mapping
is declared **in its canonical virtual-alias file**, registered in `main.cf`,
and compiled into the lookup database. A mapping written to any other path is
silently ignored and the list will not function.

The list domain and the address → recipient mapping are described in a spec
file; your job is to provision them deterministically with a reusable script.

## Fixed assets (do not modify)

- `/app/lists.spec` — the visible list spec (see format below). The local
  recipient accounts (`steward`, `warden`) already exist on the box.
- Postfix is installed; its config root is `/etc/postfix`.

## Deliverables (both required)

1. `/app/provision_lists.sh` — a self-contained, **idempotent**, **executable**
   provisioning script with this interface:
   ```
   bash /app/provision_lists.sh <spec_file> <manifest_file>
   ```
   Given a spec file it must:

   - Write the canonical virtual-alias map at the exact path
     **`/etc/postfix/virtual`** with **exactly one line per spec entry**,
     in postfix virtual(5) form `address<TAB>recipient` (entries in spec
     order). Running against a new spec must **replace** the previous
     mapping entirely — no stale entries from earlier runs may survive.
   - Register the map in `/etc/postfix/main.cf` so Postfix honors it:
     `virtual_alias_maps = hash:/etc/postfix/virtual` and
     `virtual_alias_domains = <list domain>`.
   - Build the lookup database with `postmap /etc/postfix/virtual`.
   - Write the manifest JSON to the given manifest path (format below).

   Idempotent: running it twice with the same spec must leave the same final
   state, and running it with a different spec must fully re-point the
   mapping. The list domain is **derived from the spec** (the domain shared
   by all addresses in it) — hidden specs use a different domain.

2. `/app/list_manifest.json` — the manifest produced by running your script on
   the provided spec:
   ```
   bash /app/provision_lists.sh /app/lists.spec /app/list_manifest.json
   ```

## Spec file format

Plain text; one mapping per line:

```
address<TAB>recipient
```

- Blank lines and lines starting with `#` are ignored.
- Whitespace around the fields must be tolerated and trimmed.
- All addresses share a single list domain (e.g. `lists.thornway.internal`).
- Recipients are the names of existing local accounts (no @ or routing
  prefix).

The visible `/app/lists.spec` maps `announce@` and `builders@` to `steward`
and `toolswap@` to `warden` under `lists.thornway.internal`.

## Manifest format

Valid JSON with exactly these keys:

```json
{
  "domain": "lists.thornway.internal",
  "canonical_config": "/etc/postfix/virtual",
  "lists": [
    {"address": "announce@lists.thornway.internal", "recipient": "steward"},
    {"address": "builders@lists.thornway.internal", "recipient": "steward"},
    {"address": "toolswap@lists.thornway.internal", "recipient": "warden"}
  ]
}
```

- `domain` is the list domain derived from the spec.
- `canonical_config` is the exact canonical path used.
- `lists` has one entry per spec line, **sorted by address**, each with keys
  `address` and `recipient`.

## What the grader checks

- Your script is executed unchanged against the visible spec **and against
  hidden spec files** with different domains, different addresses, and
  different recipients, so nothing about the visible spec may be hard-coded.
- The canonical file must exist at exactly `/etc/postfix/virtual`; for every
  spec address `postmap -q <address> hash:/etc/postfix/virtual` must return
  the spec recipient, and after re-provisioning with a different spec the
  old addresses must **no longer resolve**.
- `postconf -h virtual_alias_maps` must reference `/etc/postfix/virtual` and
  `postconf -h virtual_alias_domains` must contain the list domain.
- `/etc/postfix/virtual.db` must exist (postmap was actually run).
- The manifest must match the spec exactly (parsed as JSON).

## Constraints

- Deterministic and idempotent; safe to run repeatedly.
- Do not start or depend on the mail daemon; the map/database must be correct
  as configuration.
- No network access at verify time; use the installed postfix tooling
  (`postmap`, `postconf`) and standard system files.

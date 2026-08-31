# Bryony Keep — provision the announcement lists (bryony-keep)

You are the signal-officer for **Bryony Keep**, a hill watchtower. The tower
runs a tiny in-house announcement-list manager, **notimgr**, already
installed in this container:

- control tool: `/opt/keepmsg/notimgr.py` (run `python3
  /opt/keepmsg/notimgr.py read` to print the live list state, or
  `python3 /opt/keepmsg/notimgr.py check` to validate the config);
- it reads its configuration **only** from the canonical path
  **`/etc/keepmsg/lists.conf`** — a config placed at any other path is
  ignored by the manager by design (a leftover deployment wrote one to
  `/etc/keepmsg.conf`; that file is a decoy and is never read);
- the canonical path currently holds **retired** lists from the old rota;
  after your run it must describe exactly the lists declared below.

## Desired lists

The desired lists are specified in the fixture `/app/spec/spec.json`:

```json
{
  "domain": "<the single domain all list addresses belong to>",
  "lists": [
    {"address": "<list address>", "members": ["<member address>", ...]},
    ...
  ]
}
```

## Canonical config format (`/etc/keepmsg/lists.conf`)

```
# comments and blank lines are ignored
[<list address>]
members = <comma-separated member addresses>
```

Semantics (the manager and the grader both rely on them):

- addresses and member addresses are **case-insensitive**: fold them to
  lowercase;
- duplicate members collapse (deduplicate);
- a list may have an **empty** member set;
- one `[address]` section per list — if the spec declares the same list
  address twice (even with different letter case), the member sets are
  merged (union);
- `notimgr read` reports lists sorted by address and members sorted.

## Rules the grader enforces

- **Replacement semantics**: after running your tool with a spec, the
  canonical config must describe exactly the declared lists — the retired
  lists (and any lists of a previous run) must be gone.
- **Idempotent**: running the tool twice in a row is safe and produces the
  same result.
- **Invalid spec**: if any list `address` does not contain exactly one `@`
  and end with `@<domain>` (case-insensitive), or any member value is empty
  or does not contain `@`, the tool must print a diagnostic to stderr, exit
  **non-zero**, and **leave the canonical config unchanged**.
- On success the tool must exit **0**.

## Your job (two deliverables)

1. **Write `/app/configure_lists.py`** — a Python tool with this interface:

   ```
   python3 /app/configure_lists.py <spec.json>
   ```

   It reads the given spec JSON and writes the mailing-list configuration
   for the lists in that spec to the **canonical path**
   `/etc/keepmsg/lists.conf` in the format above, following all the rules
   (lowercase folding, dedup, union merge, replacement, idempotency,
   invalid-spec rejection). It must work on **any** spec file that follows
   the contract, not just the provided one — do not hard-code the visible
   lists or domain.

2. **Write `/app/report.json`** — the report the manager produces **after**
   provisioning the default spec:

   ```
   python3 /app/configure_lists.py /app/spec/spec.json
   python3 /opt/keepmsg/notimgr.py read > /app/report.json
   ```

   The report is exactly the JSON `notimgr read` prints:

   ```json
   {
     "config": "/etc/keepmsg/lists.conf",
     "lists": [
       {"address": "...", "members": ["...", "..."]}
     ]
   }
   ```

   with `lists` sorted by address, addresses and members lowercase, members
   deduplicated and sorted.

## Hidden-test behavior you should know about

The grader runs `/app/configure_lists.py` against a few *additional* spec
files: different domains, lists with no members, the same list address
declared twice (to be merged), uppercase addresses that must fold to
lowercase, a spec with **no** lists at all (the canonical config must then
exist and describe zero lists), and **invalid** specs (an address outside
the declared domain; a member value without `@`) that must be rejected with
the config left unchanged. Your tool must therefore derive everything from
the spec file it is given — hard-coding the visible lists fails the hidden
cases.

## Constraints

- Do **not** modify `/app/spec/spec.json`, `/opt/keepmsg/notimgr.py`, or the
  decoy files.
- Only the canonical path `/etc/keepmsg/lists.conf` counts: a config placed
  anywhere else is ignored and grades as a failure.
- Standard library only; no network access at run/verify time.

## Files you produce (leave at these exact paths)

- `/app/configure_lists.py` — the provisioning tool.
- `/app/report.json` — the post-provisioning manager report for the default spec.

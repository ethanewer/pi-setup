# listd behavior reference (Reedhaven Naturalist Society)

`listd` is the Society's tiny in-house mailing-list manager. This document is
the authoritative description of its behavior; `--help` on the binary repeats
the same contract.

## Invocation

```
python3 /app/listd.py --config <config.toml> --stream <commands.txt> --out <report.json>
```

The config is read from exactly the path given by `--config`. If that path is
missing, unreadable, or not valid TOML, listd exits with status 2, writes
nothing to `--out`, and prints a message on stderr.

## Config schema

```toml
[site]
domain = "..."       # optional
owner  = "..."       # optional

[[list]]
name        = "..."          # required, unique
members     = ["a@x", ...]   # optional, default []
moderators  = ["m@x", ...]   # optional, default []
open        = true           # optional, default true; false => closed list
max_members = 128            # optional, default 128 (cap on members only;
                             #  moderators never count toward the cap)
```

## Address normalization

- strip surrounding whitespace;
- if the address is written as a display name, `Name <addr>`, keep only the
  angle-bracket address;
- lowercase the result.

Duplicate entries collapse at load time (first occurrence wins). Rosters are
always reported sorted. A moderator-only address is not a member.

## Commands

Stream lines are whitespace-split tokens. Unknown command words or wrong
argument counts produce the result `"malformed"` (never fatal).

`subscribe <list> <addr>` — checks in EXACTLY this order:

1. `unknown-list` — the list name is not in the config;
2. `closed` — the list has `open = false`;
3. `duplicate` — the normalized address is already a member;
4. `full` — the member count is already at `max_members`;
5. `ok` — the address is appended to the members roster.

Note: an existing member subscribed to a *closed* list reports `closed` (rule
2 precedes rule 3). A moderator who is not a member may subscribe if the list
is open and under the cap.

`unsubscribe <list> <addr>` — checks in EXACTLY this order:

1. `unknown-list`;
2. `not-member` — the normalized address is not currently a member
   (moderator-only addresses are not members);
3. `ok` — the address is removed from the members roster.

`post <list> <sender>` — checks in EXACTLY this order:

1. `unknown-list`;
2. `accepted` — the normalized sender is a member or a moderator of the list
   (regardless of whether the list is open);
3. `rejected` — otherwise.

## Report shape

```json
{
  "site":    {"domain": "<from config or null>", "owner": "<from config or null>"},
  "actions": [{"cmd": "<verbatim stream line>", "result": "<result>"}, ...],
  "rosters": {"<list name>": ["<member>", ...sorted ascending...]}
}
```

`rosters` reflects the member set AFTER every command in the stream has been
applied, sorted lexicographically, keys sorted (the daemon emits sort_keys).

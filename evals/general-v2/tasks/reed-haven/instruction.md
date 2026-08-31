# Reedhaven Naturalist Society — provision the listd mailing lists

You are the system steward for the **Reedhaven Naturalist Society**. The
Society runs its own tiny in-house mailing-list manager, `listd`, which is
already installed in this container:

- `/app/listd.py` — the listd daemon (deterministic; no network, no clock).
- `/app/fixtures/listd-docs.md` — the authoritative behavior reference.
- `/app/fixtures/roster-source.txt` — the raw, messy historical sign-up sheet.
- `/app/fixtures/stream.txt` — the administrative command stream to replay.

`listd` reads its configuration from **exactly one canonical path**:

```
/etc/listd/config.toml
```

A config placed anywhere else is simply never honored: listd exits with
status 2 ("cannot load config") when `--config` points at a missing file.

## Your job (two deliverables)

1. **Write /app/provision.sh** — a self-contained, **idempotent** shell script
   (safe to run repeatedly, must succeed every time) that:

   - installs the canonical listd configuration at `/etc/listd/config.toml`
     (create the directory if needed), matching the required configuration
     below exactly; and
   - replays the visible administrative stream through the daemon to produce
     the roster report:

     ```
     python3 /app/listd.py --config /etc/listd/config.toml \
         --stream /app/fixtures/stream.txt --out /app/roster.json
     ```

2. **Run /app/provision.sh** so that **/app/roster.json** exists — the report
   the daemon produces for the visible stream under your canonical config.

## Required configuration content (exact)

Build `/etc/listd/config.toml` with:

- A `[site]` section with `domain = "reedhaven.example"` and
  `owner = "keeper@reedhaven.example"`.
- **List `heron-announce`**: a closed announcement list.
  - `members` = the **normalized, de-duplicated** set of every address in
    `/app/fixtures/roster-source.txt` (all six lines; duplicates collapse).
    Normalization per the docs: strip whitespace, reduce any
    `Name <addr>` form to the angle-bracket address, lowercase.
  - `moderators = ["keeper@reedhaven.example"]`.
  - `open = false` and `max_members = 40`.
- **List `tide-chat`**: an open discussion list.
  - `members = ["grace@hopper.example", "tide-fan42@stream.example"]`.
  - `moderators = ["keeper@reedhaven.example"]`.
  - `open = true` and `max_members = 3`.

The full TOML schema and every behavioral rule (check order for
subscribe/unsubscribe/post, normalization, the `max_members` cap, moderator
semantics, report shape) are documented in `/app/fixtures/listd-docs.md`.
Read it carefully before writing the config.

## What the verifier does

- Runs `/app/provision.sh` (twice — it must stay idempotent and succeed).
- Confirms the canonical `/etc/listd/config.toml` exists with the required
  lists, flags, and members.
- Confirms `/app/roster.json` matches the expected report for the visible
  stream.
- **Replays hidden administrative streams** through the daemon using YOUR
  canonical config, and compares the daemon's report against the expected
  results for each stream (closed-list refusals, cap enforcement, duplicate
  detection, moderator posting, case-insensitive matching, malformed
  commands). A config that deviates from the specification above — wrong
  members, wrong flags, wrong cap — fails these replays.
- Finally proves the failure mode: with the canonical config temporarily
  unavailable, the daemon must refuse to run (non-zero exit). That is why the
  config must live at the canonical path and be honored from there.

## Constraints

- Do not modify `/app/listd.py` or anything under `/app/fixtures/`.
- Do not rename or relocate the canonical config path.
- No network access; the daemon is fully local and deterministic.

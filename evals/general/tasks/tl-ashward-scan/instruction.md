# Ashward Workbench: persistence-artifact-scanning

The fleet-security team needs an **idempotent offline scanner** for Linux
persistence artifacts. This container ships `/app/rootfs/` — a fabricated
filesystem tree (what a forensic image of a compromised box might look like)
with planted persistence artifacts across documented locations, plus benign
lookalikes that your scanner must learn to ignore.

Your two deliverables:

1. `/app/scan_persistence.py` — the scanner CLI (pure Python 3 stdlib).
2. `/app/findings.json` — the report your scanner produces for the visible
   tree, i.e. the output of:

   ```
   python3 /app/scan_persistence.py /app/rootfs /app/findings.json
   ```

## CLI contract

```
python3 /app/scan_persistence.py <rootfs_dir> <report.json>
```

- Scans **only** the documented locations under `<rootfs_dir>` (see table
  below). Everything else in the tree is ignored.
- Writes `<report.json>` exactly per the schema below.
- Exit codes: `0` on success (root readable + report written, even with zero
  findings); `2` if the CLI is misused or `<rootfs_dir>` is missing / not a
  directory; `3` if the report could not be written. Unreadable files are
  skipped silently (best effort).
- The scanner must be **deterministic**: the same tree always yields the same
  report bytes (the grader re-runs it and byte-compares).

## Report schema (exact)

```json
{
  "root": "<the <rootfs_dir> argument exactly as passed>",
  "findings": [
    {
      "location_kind": "cron.d",
      "path": "/app/rootfs/etc/cron.d/alpha-rotate",
      "line_or_key": 2,
      "status": "allowlisted",
      "evidence": "allowlisted entry"
    }
  ]
}
```

- `root`: the CLI argument **verbatim** — no normalization, no trailing-slash
  fiddling.
- `findings`: sorted ascending by `(location_kind, path, str(line_or_key))`.
- `location_kind` is one of: `cron.d`, `crontab`, `systemd_unit`, `rc_local`,
  `shell_rc`, `ld_preload`, `at_job`.
- `path`: the artifact file's path as constructed from the root argument
  (relative subpaths joined with `/`; no `realpath`/`abspath` — symlinked
  directory targets keep the location path, e.g. `…/etc/cron.d/rot-1`).
- `line_or_key`: **int** 1-based line number for line-based kinds; **string**
  file basename for `systemd_unit` and `at_job`.
- `status`: one of `active`, `disabled`, `allowlisted`.
- `evidence`: per the rules below.

Format the file with `json.dumps(report, indent=2, sort_keys=True,
ensure_ascii=False)` plus a trailing newline.

## Scanned locations (and only these)

| kind | path(s) under `<root>` | what counts |
|---|---|---|
| `cron.d` | `etc/cron.d/` | direct children that are regular files (a symlinked dir is followed; children still report under `etc/cron.d/…`) |
| `crontab` | `etc/crontab`; `var/spool/cron/crontabs/` (direct children, regular files) | file content lines |
| `systemd_unit` | `etc/systemd/system/**`, `usr/lib/systemd/system/**`, `lib/systemd/system/**`, `run/systemd/units/**` (recursive) | regular files (never symlinks) ending in `.service .timer .socket .path .target .mount .automount .swap .slice` |
| `rc_local` | `etc/rc.local` | content lines |
| `shell_rc` | `etc/profile`, `etc/bash.bashrc`, `etc/profile.d/*.sh` (direct), `root/.bashrc`, `root/.profile`, and `home/<user>/.bashrc`, `home/<user>/.profile`, `home/<user>/.bash_profile` (direct) | content lines |
| `ld_preload` | `etc/ld.so.preload` | content lines |
| `at_job` | `var/spool/at/`, `var/spool/cron/atjobs/` (direct children) | files whose basename matches `^[0-9a-fA-F]{6,}$` |

## Line conventions (all line-based kinds)

Read each file as UTF-8 with `errors="replace"`, split on `\n`, drop a
trailing `\r` per line. Line numbers are 1-based. A **comment line** is one
whose first non-whitespace character is `#` or `;` — it is skipped entirely
(never a finding, never evidence). Lines that are empty after `strip()` are
skipped.

## Rules per kind

### cron family (`cron.d` and `crontab`; identical parsing)
For each line after dropping comments/blanks:
1. Skip environment assignments: `^[A-Za-z_][A-Za-z0-9_]*\s*=` at line start.
2. Tokenize on whitespace. If the first token starts with `@` → remaining
   tokens are the command candidates. Else, require ≥ 6 tokens whose first 5
   each match `^[0-9A-Za-z*,/\-?]+$` (time fields); remaining tokens are the
   command candidates.
3. User field: if the command candidates have ≥ 2 tokens **and** the first of
   them matches `^[A-Za-z_][A-Za-z0-9_-]*$`, drop that token (it is the user
   field). Join the rest with single spaces → `command`.
4. Skip the line if `command` is empty after `strip()`.
5. Status: `allowlisted` if the `command` is in the allowlist for this kind
   (checked first); else `disabled` if the command's first token starts with
   `#`; else `active`.
6. `allow-key` = the `command`; `evidence` = the stripped raw line (except
   `"allowlisted entry"` when allowlisted); `line_or_key` = line number.

### systemd units
Recursively scan the four dirs. For each candidate file: parse sections
linearly; within an `[Install]` section (case-insensitive header), a
non-comment line whose left side (before `=`, whitespace-stripped) is
`WantedBy` or `RequiredBy` and whose right side (comments after `#` stripped,
whitespace-stripped) is non-empty marks the unit **active**. Otherwise the
unit is **disabled** (even if it exists in the tree). `allow-key` =
basename; `line_or_key` = basename. Evidence: `"active via [Install]"`,
`"disabled: no [Install] WantedBy/RequiredBy"`, or `"allowlisted entry"`.

### rc.local
Process lines in order up to — but **excluding** — the first line whose first
token is `exit` (the classic `exit 0` fence: that line and everything after it
is inert). Each preceding non-comment, non-blank line is a finding: `allow-key`
= `evidence` = the stripped line; status `active` unless allowlisted.

### shell rc
Files as listed above. For each line after dropping comments/blanks: skip if
the first token is one of `if then else elif fi for while until do done case
esac in select function time`; skip if the first token starts with `[`, `!`,
`(`, or `{`; skip pure environment assignments matching
`^(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=\s*\S*$`. Everything else is a
finding: `allow-key` = `evidence` = the stripped line; status `active` unless
allowlisted.

### ld.so.preload
Every non-comment, non-blank line is an entry. `allow-key` = `evidence` = the
stripped line; status `active` unless allowlisted.

### at-job spools
Files (not directories) under the two spool dirs whose basename matches
`^[0-9a-fA-F]{6,}$`. `line_or_key` = basename; `allow-key` = basename;
`evidence` = `"at-job spool file"` (or `"allowlisted entry"`); status
`active` unless allowlisted.

## Allowlist (known-safe entries)

Shipped with the tree at `<root>/etc/persistence-allowlist.json` — a JSON
object mapping each `location_kind` key to a list of exact allow-keys (as
defined per kind above):

```json
{
  "cron.d": ["/opt/ashward/mux-agent"],
  "systemd_unit": ["safe-house.service"],
  "rc_local": ["/opt/ashward/beacon start"]
}
```

- If the file is missing or unparseable, treat every list as empty.
- A finding whose allow-key is listed **is still reported** — with
  status `allowlisted` and evidence `"allowlisted entry"`. The allowlist
  check runs **first**: an allowlisted item is never `active`/`disabled`.
- The allowlist file itself is not scanned (it is not a scan location).

## Probing (how the grader verifies you)

- The grader executes your CLI on `/app/rootfs` and compares the parsed JSON
  to an independent reference scanner implementing exactly the rules above.
- It re-runs the same invocation and requires **byte-identical** output
  (idempotency), and requires `/app/findings.json` to equal a fresh run.
- It then executes your CLI on **unseen** trees: a tree whose `etc/cron.d` is
  a symlink to a directory elsewhere in the tree, a tree with a *different*
  allowlist file (including allowlisted hits you must honor and lookalike
  decoys you must not flag), and an empty tree (zero findings, exit 0).
- Report parity is exact: same keys, same types (int vs string
  `line_or_key`), same sort order. A hardcoded visible `findings.json`, a
  scanner that only recognizes the visible tree, or an embedded visible
  allowlist all fail on the hidden trees.

## Constraints

- Python 3 stdlib only — no third-party packages, no network, no external
  binaries. Keep the whole run under a few seconds.
- Do not modify `/app/rootfs`; the grader recomputes expectations from it.
- If you add helper modules, keep them next to the deliverable, but a single
  self-contained `/app/scan_persistence.py` is recommended.
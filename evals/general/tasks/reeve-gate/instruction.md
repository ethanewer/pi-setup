# Task: Provision exact account and privilege state with a self-built shadow toolchain

You are root in a container that carries a real upstream build of the
**shadow** account-management suite (https://github.com/shadow-maint/shadow,
release v4.11.1, commit `eccf1c569c7ac3b9e3b535c91b6ed3c329e9ec8c`), the classic
C suite behind `useradd`, `usermod`, `groupadd`, `passwd`, `chage` and friends.

## Environment

- The pinned shadow source tree is checked out at `/opt/shadow-src` and was
  built at image creation time with the project's own autotools flow
  (`autoreconf -i && ./configure && make && make install`) into the canonical
  system locations. The distribution's account tools were replaced by this
  build. **Do not rebuild, reinstall, or modify anything under `/opt/shadow-src`
  or the installed toolchain** — the build is complete and is not the point of
  this task.
- The built account-management tools are:

  | purpose                   | path             |
  |---------------------------|------------------|
  | create/change/remove users| `/usr/sbin/useradd` `/usr/sbin/usermod` `/usr/sbin/userdel` |
  | create/change/remove groups | `/usr/sbin/groupadd` `/usr/sbin/groupdel` |
  | set passwords/hashes      | `/usr/sbin/chpasswd` `/usr/sbin/newusers` `/usr/bin/passwd` |
  | password policy / aging   | `/usr/bin/chage` |
  | group administration      | `/usr/bin/gpasswd` |

  These are the **only** account-management programs on the system.
- `jq`, `python3`, and the standard coreutils (`mkdir`, `chmod`, `chown`,
  `printf`, ...) are available. There is **no network** at trial time; nothing
  can or should be downloaded.

## The task

Write one executable script at **`/app/setup_accounts.sh`**. It takes exactly
one argument, a scenario file: `setup_accounts.sh <scenario.json>`.

The script must bring the system to **exactly** the account and privilege state
the scenario describes — groups, users, group memberships, password state,
password aging, account expiry, home directories, and filesystem paths with
their ownership and mode bits — using the built account tools above for every
account change. Coreutils may be used for path and marker-file setup.

The script must exit `0` with a short summary after applying the whole
scenario, and exit nonzero with a diagnostic when anything fails.

## Scenario schema (version "1")

A scenario file is JSON with this shape (see `/app/scenario.example.json` for a
worked example):

- `revision`: an informational string; ignore it.
- `cleanup`: list of path prefixes. The verifier wipes these from the filesystem
  before running your script (only prefixes under `/srv/` are permitted); the
  script itself does not need to clean anything.
- `groups`: list of `{"name": "...", "gid": <int>}`. Every listed group must
  exist in `/etc/group` with exactly that gid and no members beyond what
  `users[].supplementary_groups` requires.
- `users`: list of user objects:
  - `name`, `uid`: the account and its exact numeric uid.
  - `primary_group`: a group name — either a group created by this scenario or
    an existing system group such as `nogroup`. The account's primary gid in
    `/etc/passwd` must be that group's gid.
  - `home`: the home-dir path stored in `/etc/passwd` (not necessarily created).
  - `create_home`: `true` or `false`. When `true`, the directory must exist
    after the run, must be owned by the account and its primary group, and its
    mode bits must match `home_mode` (e.g. `"0700"`).
  - `shell`: the login shell stored in `/etc/passwd`.
  - `gecos`: the GECOS field stored in `/etc/passwd`; may be `""`.
  - `password`: cleartext password or `null`. When a password is given, the
    account's `/etc/shadow` entry must contain a SHA-512 hash (`$6$...`) that
    verifies against that cleartext. Never store a raw or trivially-invertible
    value. When `null`, the account must have **no usable password** (the
    shadow field must not start with `$`).
  - `locked`: `true` or `false`. The final lock state of the account's password
    (a locked account has a `!` in front of its shadow hash — exactly what
    `passwd -l` produces). A locked account may still have a valid hash set by
    `passwd -l` afterwards, and that hash must still verify.
  - `supplementary_groups`: list of group names. The user must be a listed
    **member** of each of these in `/etc/group`.
  - `min_days`, `max_days`, `warn_days`, `inactive_days`: integers or `null`.
    Non-null values must appear exactly in `/etc/shadow` columns 3–6 (the
    min/max/warn/inactive fields, counting from 0). `null` means "not
    asserted".
  - `expiry`: `"YYYY-MM-DD"` or `null`. Non-null expiry must appear in
    `/etc/shadow` column 7 as the epoch day count (days since 1970-01-01) that
    the toolchain computes — e.g. `usermod -e` produces exactly this field.
- `paths`: list of objects `{"path", "kind": "directory", "mode", "owner",
  "group", "marker"?}`. Each directory must exist with exactly `mode` (4-digit
  octal string), owned by `owner:group`. A `marker` object `{"file",
  "content", "mode"}` requires the file `path/<file>` to exist with byte-exact
  `content`, that mode, and the parent path's owner/group.

Constraints you can rely on: scenario usernames are unique, uids and gids are
unique and do not collide with anything already in `/etc/passwd` /
`/etc/group`; passwords never contain `:`; every scenario user sets `home`,
`shell`, `gecos` and `primary_group`; `groups` are listed before any use in a
`users` entry only by convention, never by requirement.

## What is evaluated

The verifier restores the pristine account databases (a snapshot taken at image
build time, before any scenario was ever applied), then runs your script once
per **hidden** scenario file (same schema, different accounts, values and edge
combinations, e.g. service accounts without homes, already-expired accounts,
locked-with-password accounts, multiple supplementary groups, markers in nested
paths) and asserts the resulting live state field by field: every column of
`/etc/passwd` and `/etc/shadow`, every group and membership in `/etc/group`,
the mode/owner/group of every home and path, and the byte content of every
marker. It also asserts that the account set after your run is exactly the
pristine set **plus** the scenario's entities — creating stray accounts or
groups fails the task.

Your script must therefore be fully data-driven: no user, group, uid, gid,
password, date or path that describes a scenario may be hardcoded, and the 
script must not overfit the example.

## Forbidden

Editing `/etc/passwd`, `/etc/shadow`, `/etc/group` or `/etc/gshadow` by hand
(redirection into them, `sed -i`, `perl -pi` on them) is forbidden and detected.
All account changes must go through the built tools.

## Developing

Run `/app/setup_accounts.sh /app/scenario.example.json` and inspect the result:

    getent passwd alice; getent group ops; id bob
    /usr/bin/passwd -S alice
    /usr/bin/chage -l alice
    grep '^alice:' /etc/shadow
    stat -c '%a %U %G %n' /srv/homes/alice /srv/data/audit /srv/data/audit/flag.txt

If you iterate, re-run the script or remove the accounts first
(`/usr/sbin/userdel -r <name>`, `/usr/sbin/groupdel <name>`); the verifier
starts each hidden case from the pristine databases, so only the script's
behaviour on a clean system matters.

Deliverable: **`/app/setup_accounts.sh`**.
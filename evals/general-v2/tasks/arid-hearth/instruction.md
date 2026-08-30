# arid-hearth — Mailing list with open-but-confirm subscription

A community runs a small mailing list on this machine. You must set up and
auto-configure the list so that joining and leaving can happen automatically,
under an **open-but-confirm** membership policy, and then prove that a
subscription round-trips and produces a confirmation.

## What is already here

A minimal, already-installed list *kernel* (the low-level store) at
`/app/list/store.py`. It manages the list state under `/app/list/state/` and
reads the policy from the config file `/app/list/list.conf`. You write the
**automation** on top of the kernel.

Kernel CLI (`python3 /app/list/store.py CMD ...`):

```
policy             -> print the current policy value from list.conf
reset              -> clear all membership state (members/pending/outbox)
subscribe ADDR      -> policy-driven join
confirm ADDR TOKEN -> promote a pending address to an active member (token must match)
unsubscribe ADDR   -> remove the address from pending and active sets
pending            -> print pending addresses as "ADDR<TAB>TOKEN"
membership         -> print active membership, one address per line, sorted
```

The kernel's `subscribe` behavior depends on the `policy` value in
`/app/list/list.conf`:

- `closed`        — `subscribe` fails (no one can join).
- `open-auto`     — `subscribe` immediately makes the address an **active** member
  (no confirmation step).
- `open-confirm`  — the open-but-confirm policy. `subscribe` puts the address
  into **PENDING** only, writes a confirmation letter (with a one-time token) into
  the list outbox, and prints `token <TOKEN>` to stdout. The address becomes an
  active member **only** after `confirm ADDR TOKEN` is called with the correct
  token.

You choose the policy by editing the config file. You may change the list of
settings in `list.conf`, but store.py must be left untouched.

## Your deliverables

### 1. `/app/list/list.conf` (configuration)

Edit it so the list adopts the **open-but-confirm** policy. Set:
`policy = open-confirm`.

### 2. `/app/list_ops.sh` (the automation)

An executable shell script that auto-handles a subscription session. It must
support exactly these invocations and exit statuses:

- `list_ops.sh subscribe ADDR`
  - Runs the join through the kernel.
  - Under open-confirm: the address goes to PENDING, a confirmation is produced,
    and the script echoes the token on a line that starts with `token ` (i.e.
    the exact line `token <TOKEN>` on stdout). Exit 0 only if the join was
    accepted by the policy; otherwise exit non-zero.
  - It must ALSO append a line to the subscription log `/app/subscribe.log`
    recording the event (see format below).
- `list_ops.sh confirm ADDR TOKEN`
    - Runs the confirmation. Exit 0 if the token promoted the address to active,
      exit non-zero if the token is wrong or there is nothing pending.
    - On success it appends a confirmation event to `/app/subscribe.log`.
- `list_ops.sh unsubscribe ADDR`
    - Removes the address from the list (both pending and active). Exit 0.
- `list_ops.sh membership`
    - Prints the ACTIVE membership set, one address per line, sorted ascending.

Any other usage should print a short usage message and exit non-zero. The
script must work when called with a fresh, previously-reset list state.

### 3. `/app/subscribe.log` (the round-trip evidence)

A log proving a real subscription round-trip ran under the policy. Each line is
a single event. Use exactly this shape (your real token, timestamps optional):

```
event=pending address=ADDR status=pending policy=open-confirm token=TOKEN
event=confirm address=ADDR status=confirmed policy=open-confirm
```

The log must end up containing **at least one line with `status=pending` and
at least one line with `status=confirmed`**, produced by actually performing a
subscribe + confirm on this machine (the automation appends these lines itself
when you run it). Pick any address of your own (e.g. `admin@example.test`).

## Constraints / gotchas

- Do not modify `/app/list/store.py`. Do not bypass the policy.
- Confirmation must be mandatory in a certain way: under open-but-confirm, a
  subscribed but **unconfirmed** address must NOT appear in `membership`. Only a
  correct token promotes it.
- Confirm with a **wrong** token must not promote the address.
- `unsubscribe` removes an address whether or not it was ever confirmed.
- All automation must run on this container with the standard `bash` and the
  preinstalled kernel; no network is required.

## Success check

A correct setup yields, for example:

```
$ python3 /app/list/store.py policy
open-confirm

$ /app/list_ops.sh subscribe bob@example.com
token 9e5b2f1c0a4d

$ /app/list_ops.sh membership
     (nothing printed yet — bob is PENDING, not active)

$ /app/list_ops.sh confirm bob@example.com 9e5b2f1c0a4d
$ /app/list_ops.sh membership
bob@example.com

$ /app/list_ops.sh unsubscribe bob@example.com
$ /app/list_ops.sh membership
     (empty)
```

Build your `list_ops.sh` so it reproduces this exact flow and writes the two
event lines to `/app/subscribe.log`.
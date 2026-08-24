# Recover, configure, and run the self-hosted mailing-list platform (hard)

A nonprofit's **announcement list** platform was just rebuilt from backups on a
fresh host, but the operator was interrupted **mid-provisioning**. Two processes
are down, some receiver directories are missing, and mail is being silently
dropped. You must bring the platform up, complete provisioning, and drive the
confirmation and delivery workflows end to end, verifying every outcome through
the **logs**, because the MTA is silent about dropped local mail.

## The platform

`/app/mailplatform/` contains two long-running Python services (do **not**
modify either):

- `mailservice.py` — the SMTP intake service (Postfix role). Listens on
  `127.0.0.1:2525`, accepts RFC5321 SMTP, and routes:
  - `@lists.example.test`  -> queued to `/srv/list/queue/` for the manager,
  - `@example.test`        -> stored as `<seq>.eml` under `/srv/mail/<local>/`.
    If `/srv/mail/<local>` does **not** exist, the message is **dropped** with a
    `delivery_failed <local> <seq>.eml` line in `/srv/mail/logs/smtpd.log`
    (the sender still gets `250 ok`).
- `listmgr.py` — the list manager (Mailman role). Watches `/srv/list/queue/`.
  - `subscribe@lists.example.test` -> mails a confirmation back to the sender
    (subject `CONFIRM <token>`, token = 40 hex chars).
  - `confirm@lists.example.test`   -> on a correct token + matching
    `X-Confirm-Address` header, appends the address to `/srv/mail/confirmed.txt`
    and mails a welcome.
  - anything else -> a list post: it emails **every** subscriber (the config
    subscribers **plus** anyone in `confirmed.txt`).

Read both scripts before touching anything — the point is to learn the exact
headers and logs you must reconcile.

## Current on-disk state (the traps)

- `/etc/maillists/announce.json` already lists subscribers `alice`, `bob`, and
  **`dave`**, plus `admin`. Leave this file **unchanged**.
- Maildirs for `alice`, `bob`, and `admin` exist under `/srv/mail/`.
- **`/srv/mail/dave` is missing** even though `dave@example.test` is a listed
  subscriber. Any campaign advertised to the list will be **silently dropped**
  for dave (the MTA answers `250` while logging `delivery_failed dave ...`).
- `/srv/mail/carol` is also missing; Carol will need it once she confirms.
- Nothing is running. The logs directory is empty.

## Do this

### Step 1 — survey and provision
Read `/app/mailplatform/*.py` and the JSON config. Then:
- create `/srv/mail/dave` (mode `0700`) so the listed subscriber can actually
  receive mail;
- create `/srv/mail/carol` (mode `0700`) so Carol can subscribe and receive her
  confirmation.

### Step 2 — start both daemons
Start each as a **long-running background process** (they must keep running):
- `python3 /app/mailplatform/mailservice.py --port 2525`  -> `/srv/mail/logs/smtpd.log`
- `python3 /app/mailplatform/listmgr.py`                  -> `/srv/mail/logs/listmgr.log`

When you are done, `pgrep -f` must still find both, and an SMTP connect to
`127.0.0.1:2525` must receive `220`.

### Step 3 — confirmation workflow (new member)
Enroll **`carol@example.test`**:
1. Send `carol@example.test` -> `subscribe@lists.example.test` a short message
   with `From: carol@example.test`.
2. Read the returned `CONFIRM <token>` message out of `/srv/mail/carol/`.
3. As carol, send a message to `confirm@lists.example.test` with subject
   `CONFIRM <token>` (exact token) **and** header `X-Confirm-Address:
   carol@example.test`. Only a correct token confirms.
4. Confirm that `/srv/mail/carol/` now contains the **welcome** email, that
   `carol@example.test` is recorded in `/srv/mail/confirmed.txt`, and that
   `listmgr.log` logs the confirmation (`subscribed carol@example.test`).

### Step 4 — campaign 1 (recovery coverage)
Post a newsletter:
- from `admin@example.test` -> `announce@lists.example.test` **twice** (two
  separate posts, each with subject `Member briefing` and body containing the
  literal marker `MKT-ALPHA-1`).

Because dave has a Maildir now, all three configured subscribers (alice, bob,
dave) must receive a copy. **Verify in the logs**: `listmgr.log` must show a
`deliver ... ok` line for *each* of alice, bob, dave for *each* post, and each of
their Maildirs must hold an `.eml`. If dave's copy is missing, inspect
`smtpd.log` for the tell-tale `delivery_failed` line, fix the cause, and re-post.

### Step 5 — campaign 2 (covers the new member)
Post `admin@example.test` -> `announce@lists.example.test` once more, body with
literal marker `MKT-BETA2`. Now the recipient set is the three configured
subscribers **plus** carol. Verify each of alice, bob, dave (2nd copy) and carol
(this 1nd post) has a copy, and the log shows a `deliver` ok line per recipient.

### Step 6 — health and final state
Leave running: both daemons, the config file, the four Maildirs, the
**confirmed.txt** file, and a `/app/client.py` (your reusable Python client).
The final mailbox contents and the logs are what get re-verified.

## Success criteria (what the verifier asserts)
1. Both daemons alive and SMTP `220` at `127.0.0.1:2525`.
2. `/srv/mail/dave` and `/srv/mail/carol` exist as directories.
3. `/srv/mail/confirmed.txt` contains `carol@example.test`.
4. Final mailbox contents: alice, bob, dave, carol each have **≥2** `.eml` files
   (dave must be covered by both campaigns; carol by welcome + campaign 2).
5. `listmgr.log` contains a `subscribed carol@example.test` line and `deliver`
   `ok` lines covering alice, bob, dave, and carol.
# Self-hosted mailing-list service (Mailman-style) over an SMTP mail service

A small nonprofit runs an **announcement mailing list** for its members. The platform is a
**two-process inbound mail service**, similar to a Mailman list engine fronted by a
Postfix-style SMTP (MTA) service, implemented here in Python:

- `/app/mailplatform/mailservice.py` — the **SMTP intake service** (Postfix role): accepts
  RFC5321 SMTP on `127.0.0.1:2525`, delivers local mail into per-user Maildirs, and
  routes list-addressed mail into a list queue for the manager.
- `/app/mailplatform/listmgr.py` — the **list manager daemon** (Mailman-3 role): watches
  the list queue and handles subscription confirmation and list posts.

Do **not** modify either script. Your job is to **configure this multi-service system,
run it as long-running processes, and prove both the confirmation workflow and the
delivery workflow end to end**. Nothing is running and nothing is configured yet.

## Address conventions

The service serves exactly two domains:

- `@example.test` — normal local users. A message to `alice@example.test` is stored as a
  file `<seq>.eml` in user Alice's Maildir `/srv/mail/alice/`. The Maildir directory must
  already exist; if it does not, the server logs `delivery_failed` to its own log and the
  message is not stored.
- `@lists.example.test` — list-managed addresses, e.g. `announce@lists.example.test`.
  These are queued to `/srv/list/queue/` and processed by the list manager.
- Any other domain is rejected (`550`).

## Step 1 — configure the list and provision users

Create these Maildirs (mode `0700`): `/srv/mail/alice`, `/srv/mail/bob`,
`/srv/mail/admin`. (Also create `/srv/mail/carol` before the subscribe step.)

Write the list configuration to `/etc/maillists/announce.json`:

```json
{"list":"announce","domain":"lists.example.test",
 "subscribers":["alice@example.test","bob@example.test"],
 "admin":"admin@example.test"}
```

The list manager reads this file each time it processes a queued message.

## Step 2 — start both daemons as background processes

Start each as a long-running background process (append their output):

- SMTP intake (Postfix role): `python3 /app/mailplatform/mailservice.py --port 2525`
  → log to `/srv/mail/logs/smtpd.log`
- List manager (Mailman role): `python3 /app/mailplatform/listmgr.py`
  → log to `/srv/mail/logs/listmgr.log`

Keeping both services running is a key requirement: when you finish, `pgrep -f`
must still find both processes, and an SMTP client connecting to `127.0.0.1:2525`
must get the `220` greeting.

## Step 3 — drive the confirmation workflow (subscribe → confirm)

For a new member **carol@example.test**:

1. Create `/srv/mail/carol` so Carol can receive mail.
2. Send from `carol@example.test` to `subscribe@lists.example.test` a short subscribing
   message (`From: carol@example.test`). The manager reads it from the queue and mails a
   **confirmation** back to Carol: subject `CONFIRM <token>` where token is 40 hex chars.
3. Read the confirmation message from `/srv/mail/carol/`.
4. Reply to `confirm@lists.example.test` as Carol: the message must have
   `Subject: CONFIRM <token>` (the exact token from step 3.2) **and** a header
   `X-Confirm-Address: carol@example.test`. Only a correct token confirms.
5. After a correct confirmation, `carol@example.test` is appended to
   `/srv/mail/confirmed.txt` (one address per line) and a welcome email is delivered to
   `/srv/mail/carol/`.

## Step 4 — test the delivery workflow

1. Post a first newsletter: send from `admin@example.test` to `announce@lists.example.test`.
   Every current subscriber (alice, bob) must receive a copy: a `.eml` file in each of
   `/srv/mail/alice/` and `/srv/mail/bob/`, and `listmgr.log` must show a
   `deliver … alice@example.test ok` and `deliver … bob@example.test ok` line.
2. Post a second newsletter the same way. Now **alice, bob, and carol** must each receive
   a copy (carol was added by confirmation).

## Done

Leave running: both daemons; the config file; the Maildirs; and `/app/client.py` (your
reusable Python client). The final mailbox contents and logs are what get re-verified.
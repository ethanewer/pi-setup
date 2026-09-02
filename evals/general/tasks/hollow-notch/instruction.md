# hollow-notch — Palisade store provisioning & service repair

You are the on-call operator for a small, invented distributed store called
**palisade** running on a single Ubuntu 24.04 host with **no systemd** (the
container has no init; you start daemons yourself). The store consists of
**three JVM daemon roles** (`primary`, `data`, `secondary`) that together form a
three-node cluster. The machine was handed over in a broken state on four
fronts:

1. **Name resolution / hostname are broken** — the hostname is the unqualified
   `host3`, `/etc/hosts` has no entry for the site's intended name, and
   `/etc/nsswitch.conf` was fragmented to `hosts: files` only.
2. **The cluster is not running** — no palisade daemon has been started, so the
   RPC port is closed and no status report exists.
3. **List mail is misconfigured** — postfix was repointed to a bogus external
   `relayhost`, so mail sent for the local announcement list would be thrown out
   (or fail) instead of being delivered to the local subscriber mailboxes.
4. **The provisioning must persist** — the verifier runs its own checks *after*
   your setup has finished, and will re-run your script; the fix must be durable
   file configuration, not leftover shell environment or one-shot commands.

Your job is to write **one idempotent provisioning script** `/app/setup.sh`,
run it so the live container is fully repaired, and produce the cluster health
report `/app/status.json`.

---

## Deliverables

| Path | What it is |
|------|------------|
| `/app/setup.sh` | Your idempotent provisioning script. When executed (possibly again, and possibly with **a different site descriptor argument**), it repairs the machine, starts/keeps the cluster, writes `/app/status.json`, and delivers the list notice. |
| `/app/status.json` | The healthy cluster snapshot written by running `/app/setup.sh` against the **default** site descriptor. |

The verifier will (a) re-execute `bash /app/setup.sh` (no arguments → default
site), (b) independently check the repaired live system state, and (c) re-run
your script against **hidden site descriptors** to prove it generalizes.

---

## The site descriptor (the input your script must handle generically)

`/app/palisade/site.conf` is the default descriptor. It is a plain `key = value`
file (`#` starts a comment). The keys are the only ones that matter:

```
host=palisade-core.hollow.farm
primary_port=26100
data_port=26101
secondary_port=26102
capacity_mb=65536
```

* `host` — the intended **fully-qualified name** of this site (letters, digits,
  `-`, `.`). It must resolve to `127.0.0.1` after your fix.
* `primary_port` / `data_port` / `secondary_port` — the RPC ports the three
  roles bind (each role binds exactly one).
* `capacity_mb` — per-node configured capacity in MiB; the cluster's reported
  capacity is aggregated across the three nodes.

**Your script must accept the descriptor path as its (optional) first argument:**

```
bash /app/setup.sh [SITE_CONF]
```

* No argument → use `/app/palisade/site.conf`.
* With an argument → use that file (hidden tests pass alternate descriptors).

### Descriptor validation (hidden tests rely on this)

A **malformed** descriptor (e.g. a missing/empty `primary_port`, a missing
`host`, a non-integer or out-of-range port, a zero/negative `capacity_mb`) must
make `/app/setup.sh` **abort cleanly**: print an error to stderr and `exit` with a
**non-zero** code, **without** starting daemons, writing `/app/status.json`, or
damaging the already-running cluster. Hint: validate the whole descriptor before
performing any side effect, and never write the report for an invalid input.

---

## What `/app/setup.sh` must accomplish when handed a *valid* descriptor

### 1. Repair name resolution + hostname (and persist it)
* Add `127.0.0.1  <host>` to `/etc/hosts` if not already present.
* Restore `/etc/nsswitch.conf` so its `hosts:` line includes **both** `files`
  and `dns` (e.g. `hosts: files dns`). Detect the broken line and fix it.
* Set the hostname to `<host>` and write `/etc/hostname` so the FQDN survives.
* After this, `getent hosts <host>` (and localhost lookups) must resolve to
  `127.0.0.1`, and the changes must be visible from later processes — i.e. they
  must live in the config files, not just the current shell.

### 2. Start and keep alive the three JVM daemons
Run exactly three daemon processes, one per role, from the provided jar:

```
java -jar /app/palisade/palisade.jar <site-conf> <role>
```

with role ∈ `{primary, data, secondary}`. They must keep running in the
background (there is no systemd — use `nohup … &`/`disown`). They must listen on
their role's configured RPC port. If the script is re-run, it should cleanly
replace the previous daemon set (a previous run's daemons must not survive/litter
the port). At any moment exactly the three roles of the most recent site must be
the only `palisade.jar` processes alive.

### 3. Serve a healthy cluster report on the primary RPC port
Each daemon answers the TCP request line `GET /status` (one line) on its role
port with a **single-line JSON** object, then closes the connection:

```json
{"name":"palisade","host":"<host>","health":"cluster","online":true,
 "capacity":<bytes>,"nodes":[{"role":"primary","port":<p>,"online":true},
 {"role":"data","port":<p>,"online":true},
 {"role":"secondary","port":<p>,"online":true}]}
```

* `online` is true **only when all three nodes are actually alive** (fresh
  heartbeats), and `nodes[].online` reflects each member's real liveness.
* `capacity` is `capacity_mb * 3 * 1024 * 1024` (bytes, aggregated).
* Your script must confirm the report is healthy before writing it out.

### 4. Write `/app/status.json` (the report deliverable)
Query the primary RPC port for `GET /status` and write the returned JSON object
to `/app/status.json`. This is the artifact the verifier reads; it must describe
the **default** site when running with no argument.

### 5. Point outbound list mail at the local mailboxes and deliver
The announcement list is `palisade-announce@hollow.farm`; the subscribers are the
local OS accounts **sable**, **rona**, **trio** (they already exist; their mail
spool is `/var/mail/<user>`).

* Configure postfix so that this must be delivered **locally**, never leaked to
  an external relay:
  * `mydomain = hollow.farm` and include the list domain in `mydestination`;
  * **remove/disable the bogus `relayhost`** (the hijacked outbound relay) so the
    list is not thrown outbound;
  * keep loopback-only interfaces, IPv4.
* Declare the list in `/etc/aliases` as
  `palisade-announce: sable, rona, trio` and rebuild aliases so postfix fans the
  one message out to the three subscriber mailboxes.
* (Re)start/load postfix and send one notice to `palisade-announce@hollow.farm`
  whose body contains the exact marker line `PALISADE-RING-4421`. After delivery
  the marker must appear in each of `/var/mail/sable`, `/var/mail/rona`,
  `/var/mail/trio`.

---

## What the verifier checks (so you don't miss anything)

For the **default** site, after re-running `bash /app/setup.sh`:
* the script exits `0`;
* exactly three `palisade.jar` JVM processes are alive;
* `GET /status` on port `26100` returns a healthy JSON report (3 nodes, all
  online, `online:true`);
* `/app/status.json` exists, parses, has `host == palisade-core.hollow.farm`,
  reports 3 online nodes and `capacity == 65536*3*1024*1024`;
* `getent hosts palisade-core.hollow.farm` → contains `127.0.0.1`; the fix is in
  `/etc/hosts`, `/etc/hostname`, and the `hosts:` line of `/etc/nsswitch.conf`;
* `/etc/aliases` declares the list; `/etc/postfix/main.cf` has `mydestination`
  covering `hollow.farm` and **no** `relayhost`;
* each of `/var/mail/sable`, `/var/mail/rona`, `/var/mail/trio` contains
  `PALISADE-RING-4421`.

Then it re-runs your script against hidden descriptors:
* **Valid alternate sites** — e.g. a descriptor with a different `host`
  (still under `hollow.farm`), different ports, and a different `capacity_mb`
  (including a small capacity). Your script must start those roles on the new
  ports, make the new host resolve and persist, and serve a healthy `online:true`
  report naming that host. It must handle **any** valid set of ports/capacity,
  not a hard-coded value.
* **Malformed descriptor** — must `exit` non-zero and leave an already-healthy
  cluster and its `/app/status.json` untouched.

Your script must be **idempotent**: re-running it (as the verifier does) must not
crash, hang, or leave duplicate daemons.

## Constraints & tips

* Do **not** modify `/app/palisade/palisade.jar`. You may read
  `/app/palisade/site.conf`. You *must* repair `/etc` files.
* There is no `systemd`; start postfix with `postfix start` (stop it first if it
  is already running). The palisade daemons have no init supervision — keep them
  alive with background jobs from your script and make sure they are not torn
  down when your script exits.
* Work only inside the container you are given; the verifier runs in that same
  live container afterwards and inspects its final state.
* You may find these tools present and useful: `java`, `jq`, `getent`, `sed`,
  `postfix`, `sendmail` (from postfix), `bash` `/dev/tcp`, `pgrep`/`pkill`.

Produce `/app/setup.sh`, run it to fully repair the container and generate
`/app/status.json`, then stop. A correct, general, durable provisioning script
earns a reward of 1; any missing daemon, offline report, unresolved host,
non-persistent fix, leaked list mail, or broken hidden case earns 0.

# A single-host network has no broadcast address

## Situation

`/app/src` is a shallow, pinned clone of the psutil project
(`https://github.com/giampaolo/psutil`), checked out at a specific upstream
commit, and installed from that tree in editable (development) mode, so the
code you import is exactly the checked-out Python source (plus the compiled
C extension built from that tree). Python 3.12, pytest, pytest-instafail and
pytest-xdist are installed. The task does not depend on the network:
everything you need is already in the image, and the checkout is pinned to a
specific commit. Do not go looking for — or fetch — the upstream fix, and do
not rewrite the clone's history; the verifier proves the upstream fix commit
is not reachable from the working clone (see below).

psutil is a cross-platform library for system introspection. The function
you care about is `psutil.net_if_addrs()`: for every network interface it
returns a list of named tuples with fields
`(family, address, netmask, broadcast, ptp)`. The documented contract of
the `broadcast` field: the interface's broadcast address, or `None` if the
interface/family has no broadcast address.

## The bug

Some hosts carry an interface configured with a **/32 IPv4 address** — a
*single-host network*, where the netmask is `255.255.255.255`. This is
common on VPNs and cloud instances: the whole "network" is one address, the
host itself. Such a network has **no broadcast address by definition**, so
the address tuple must report `broadcast = None`.

On this checkout, that is not what happens. For a /32 IPv4 address, the
networking-addresses function reports the **interface's own IP address** in
the broadcast field. Tooling that derives broadcast addresses from this
value, or copies subnet configurations from it, gets a nonsense result that
is identical to the host's own address.

Reproduce it directly (the value that ends up in the `broadcast` field is
computed from the address and netmask):

```
python3 /app/probe_netinfo.py
```

The probe builds the address ntuple exactly as `net_if_addrs()` does for a
/32 interface and prints what the code derives as the broadcast:

```
broadcast_addr() for 89.234.156.160/32 -> '89.234.156.160'   # BUG: must be None
```

A /32 has no broadcast; the expected result is `None`. On real hosts the
same bogus value is what lands in the `broadcast` field of the tuple that
`net_if_addrs()` returns for that interface.

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that:

- A single-host network — IPv4 with netmask `255.255.255.255` (/32) — has
  broadcast `None`, and the `broadcast` field that `net_if_addrs()` reports
  for such an interface is `None`.
- Ordinary networks keep their real broadcast addresses: `127.0.0.1/8`
  (`255.0.0.0`) still has broadcast `127.255.255.255`;
  `192.168.1.7/24` still has broadcast `192.168.1.255`, and so on.
- An IPv6 single-host address (prefix length 128) is treated the same way:
  no broadcast.

Run the probe after your change; it must print `None` for the /32 case and
exit 0. Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_misc.py -q -p no:cacheprovider
```

The project's own tests are green at the pinned commit; keep them that way
(e.g. also `python3 -m pytest tests/test_system.py -k "net_if_addrs or net_if_stats" -q -p no:cacheprovider`).
Look at how the address tuples are assembled and where the broadcast value
for an address/netmask pair is derived, and change only what the fix
requires, in place. The verdict on your fix is made by the verifier, which
checks a regression test that upstream added for exactly this behaviour,
plus additional cases over inputs that test does not use.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree remains at the pinned
  commit, that only the minimal source surface of the fix is modified (no
  extra tracked files, and no new files anywhere in `/app/src`), and that
  the loaded `psutil` code is exactly the code compiled from that tree (an
  interception wrapper such as a `sitecustomize.py` or a shadow package is
  detected).

## What the verifier checks

1. The tree is still at the pinned commit, the upstream fix was not fetched
   by the agent, no extra tracked files were changed, no new files were
   added anywhere in `/app/src`, and the loaded `psutil` functions execute
   exactly the code compiled from the checked-out source (an interception
   wrapper is detected). The upstream regression test kept in `/opt/golden`
   is also verified by digest, so it cannot be defused.
2. The project's own upstream regression test for this behaviour passes
   (a single-host /32 IPv4 address must yield no broadcast).
3. The project's own existing test suite still passes: `tests/test_misc.py`
   and the `net_if_addrs` / `net_if_stats` slice of `tests/test_system.py`.
4. Hidden cases over inputs the upstream test does not use pass: other /32
   IPv4 addresses, IPv6 single-host /128 networks, a guard that normal
   networks (IPv4 `/8`–`/31` and IPv6 `/64`) still produce their real
   broadcast addresses and that entries without a netmask stay `None`, and
   the address-tuple assembly path: a `/32` entry fed through
   `psutil.net_if_addrs()` must report a `None` broadcast field while an
   ordinary `/8` entry still reports its real broadcast.

Deliverable: the repaired `/app/src` tree.
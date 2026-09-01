# relay-bank: provision and finish the bench

You are the site operator for **relay-bank**, a small internal service that
fronts a three-node JVM cluster plus a mail relay. The box is a fresh Ubuntu
24.04 container with Docker infra (`java`, `postfix`, `tcpdump`, `whois`,
`jq`, `sudo`, `curl`, `netcat`). There is **no systemd / init system**, so
daemons are supervised by scripts, not by system services. Work entirely in
`/app`.

Fixed assets (do **not** modify them):

- `/app/lib/relay.jar`      — the tiny JVM daemon (peer + reporter binaries).
- `/app/fixtures/traffic.pcap`   — the capture to turn into a flow table.
- `/app/fixtures/valediction.txt` — the terminal ending message (step 7).

---

## Deliverables (all must exist under `/app`)

1. `/app/setup.sh`  — self-contained, **idempotent** provisional script
   (safe to run several times) applying every task below.
2. `/app/status.json` — the healthy cluster report.
3. `/app/pcap_to_netflow.py` — the flow-table parser.
4. `/app/answer.txt` — the verbatim terminal ending text.

Grading executes `/app/setup.sh` first on a fresh container, then checks each
result. Everything that must persist (DNS fix, hostname, mail config, login
shell) has to live in real config files, not in memory.

---

## 1. Keep the cluster alive and report it healthy

`relay.jar` has two entrypoints:

```
java -cp /app/lib/relay.jar Relay peer <role> <port>
java -cp /app/lib/relay.jar Relay reporter <http-port> <c1:port1> <c2:port2> <c3:port3>
```

Start and keep alive the **three peer replicas** `companion-a` (`18081`),
`companion-b` (`18082`), `companion-c` (`18083`), all binding loopback TCP,
answering `PING` with `PONG`, and refreshing a heartbeat under `/app/run/`.
They must stay up; if one dies your supervisor must bring it back. Then start
one `reporter` on **`18490`** that probes all three and writes
`/app/status.json` as JSON:

```json
{"cluster": "relay-bank", "healthy": true,
 "members": [{"role": "companion-a", "port": 18081, "up": true},
              {"role": "companion-b", "port": 18082, "up": true},
              {"role": "companion-c", "port": 18083, "up": true}],
 "expected": 3}
```

`healthy` must be `true` and every node `up` while all three peers are
reachable. Grading opens the three peers, requests
`http://127.0.0.1:18490/` for a healthy report, and reads `/app/status.json`.

## 2. Repair name resolution and hostname persistently

- Apply the intended hostname **`relay-bank-vnode`** and record it in the
  persistent `/etc/hostname`, so `hostname` reports it.
- Make **`relay-bank.internal`** resolve to **`10.9.9.77`**. This fix must
  survive the grading run because it is stored in the **resolver/hosts
  configuration files** (e.g. `/etc/hosts`), not transient.

## 3. Canonical mailing-list config with local delivery

- Put the canonical mailing-list map at the canonical path
  **`/etc/postfix/relay_mapping`** (a postfix hashtable) describing each
  relay-bank list address under the domain `relay.internal` as delivering to
  the **local** account `mailreader`, e.g.
  `relay.briefs@relay.internal  local:mailreader`.
- Make postfix honor it: add `transport_maps = hash:/etc/postfix/relay_mapping`
  to `/etc/postfix/main.cf`, then build it with `postmap`.
- Declare the same list as an alias in `/etc/aliases` mapping onto the local
  account, and regenerate the alias database with `postalias`.

Grading reads `/etc/postfix/relay_mapping`, `/etc/postfix/main.cf`,
`/etc/aliases` + the rebuilt `*.db` maps, and confirms list mail targets the
existing local `mailreader` account in `/etc/passwd`.

## 4. Parse the capture into network flows

`/app/pcap_to_netflow.py` is a **robust CLI parser**:

```
python3 /app/pcap_to_netflow.py <input.pcap> <output.json>
```

It reads a libpcap file (Ethernet link type, either byte order), parses the
IPv4 packets, and **aggregates packet-level records into distinct flows**
keyed by the IP 5-tuple `(src_ip, src_port, dst_ip, dst_port, protocol)`,
where protocol is `"TCP"` or `"UDP"`. It runs on the provided
`/app/fixtures/traffic.pcap` and **on hidden pcap files**, so it must:

- merge every packet sharing a 5-tuple into one record: `packets` = count,
  `bytes` = sum of the IP total length, `first_ts`/`last_ts` = earliest /
  latest timestamps (seconds as a float);
- **skip** non-IPV4 frames (e.g. ARP) and unsupported transports;
- **sort** the records by `(first_ts, src_ip, sport, dst_ip, dport, proto)`,
  so it tolerates out-of-order packet timestamps; handle flows seen on just
  one packet, zero-payload (e.g. DNS) packets, and distinct flows that share
  IPs but differ only by port;
- emit an array of records (lines) exactly like:

  ```json
  {"src_ip": "10.20.30.5", "sport": 4001, "dst_ip": "10.0.0.10", "dport": 443,
   "proto": "TCP", "packets": 4, "bytes": 2208,
   "first_ts": 1600000000.0, "last_ts": 1600000000.0003}
  ```

- **fail safely**: for input that is not a structurally valid pcap —
  unrecognized magic bytes, a truncated/half-written packet record, an
  unsupported link type — the parser must exit **non-zero**, print nothing to
  stdout (an stderr message is fine), and **not create** the output file.

## 5. Persist the default login shell

The local list account **`mailreader`** is currently limited to
`/usr/sbin/nologin`. Change its **default login shell** to **`/bin/bash`**,
permanently, so the account database lookup reports `/bin/bash` (use
`chsh`/`usermod`). Leave it able to log in.

## 6. Capture the terminal ending verbatim

`/app/fixtures/valediction.txt` is the exact message shown at the operator's
sign-off. Capture it **byte-for-byte, unmodified** into `/app/answer.txt`:
the file must contain **precisely** the fixture's bytes — all characters,
line breaks, trailing newline, spacing, and capitalization — with no
trimming, rewording, or reformatting.
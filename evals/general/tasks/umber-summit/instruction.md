# Umber Summit — Ridgeor Security Operations

You are a security-operations engineer for **Ridgeor**, a fictional edge-telemetry
provider. Your shift produces four hardened artifacts under `/app`. Everything runs
in a single offline container; every tool you need is already installed.

The deliverable contract is exact. Use **literal** paths and **exact** schemas.

---

## Stage 1 — Rule-driven log detection

Write an **executable** script `/app/detect.sh` that applies a JSON rule set to
WSSC log files and produces two report files. Also author the scenario's rule set
at `/app/rules.json`.

### Inputs

- `/app/logs/access.log` and `/app/logs/auth.log` (provided). Every recorded line
  has the form
  `[<ISO ts>] src=<ip> <rest...>` — a source IP is the token immediately after
  `src=`. Some lines have **no** `src=` at all and must still be scanned.
- A **rules JSON** — either `/app/rules.json` (default) or any path given as an
  argument. Each rule object is
  `{ "id": string, "pattern": string, "threshold": int, "severity": string }`
  where `pattern` is a Python regular expression matched with
  `re.search` against each line.

### Interface

```
detect.sh [RULES] [LOG1 LOG2 ...]
```

Make `/app/detect.sh` executable (`chmod +x /app/detect.sh`). The verifier runs
it with `bash /app/detect.sh ...`, so both ports must work.

- If `RULES` is omitted it defaults to `/app/rules.json`.
- If no `LOG...` are given, the script scans `/app/logs/access.log` and
  `/app/logs/auth.log`; otherwise it scans exactly the named files.
- Outputs **always** go to the fixed paths `/app/alert.json` and `/app/report.json`.

### Semantics (implement these exactly)

For each rule, scan **every** given log file line; a line is a *match* for that
rule when `re.search(pattern, line)` succeeds.

- **matches** = number of matching lines across all given files.
- **ips** = the sorted-up deduplicated list of source IPs from matching lines only
  (read the `src=IP` token; a matching line with no `src=` counts toward
  `matches` but adds no IP).
- A rule **fires an alert** when `matches >= threshold`.

### Malformed-input handling (probed by hidden cases)

- A rule object with a **missing `pattern`** (or a non-string) behaves as an empty
  pattern and matches nothing.
- A rule with a **missing `threshold`** defaults to `0`.
- A rule with a **missing `severity`** defaults to `"info"`.
- An **unparseable `pattern`** (one that would raise `re.error`) matches nothing —
  never crash.
- A rules file that is **missing or not valid JSON**, or a code `rules` key, yields
  zero rules (the script must run and emit empty structures).
- Missing/unreadable log files, or empty log files, are fine — they contribute no
  matches.

### Output formats

`/app/alert.json`:

```json
{
  "timestamp": "2026-02-03T23:00:ZZZ",
  "alerts": [
    { "id": "auth_rejection", "severity": "high", "matches": 8, "ips": ["10.0.0.99", "172.16.9.10"] }
  ]
}
```

- `timestamp` is an ISO-8601 UTC string (use `date -u +%Y-%m-%dT%H:%M:%SZ`).
- `alerts` contains **only** the rules whose `matches >= threshold`.

`/app/report.json`:

```json
{
  "timestamp": "...",
  "statistics": {
    "<rule id>": {
      "id": "...", "pattern": "...", "threshold": 4, "severity": "high",
      "matches": 8, "unique_ips": 2, "ips": ["10.0.0.99", "172.16.9.10"]
    }
  },
  "events": [ { "rule": "<rule id>", "src": "<ip or null>", "line": "<full line>" } ]
}
```

`events` must contain an entry for **every** matched rule/line pair. `src` is
`null` when the matching line carried no IP. `statistics` must contain an entry for
**every** rule (even non-firing ones, with `matches: 0` and `ips: []`).

Author `/app/rules.json` with at least these five rules (exact ids/patterns):

| id | pattern | threshold | severity |
|----|---------|-----------|----------|
| `auth_rejection` | `authentication was rejected` | 5 | high |
| `syn_scan` | `SYN port scan` | 3 | medium |
| `ping_sweep` | `ping sweep` | 2 | medium |
| `no_source` | `no source` | 1 | low |
| `metric_push` | `metric-push` | 7 | notice |

> Set `metric_push`'s threshold so that, given the visible logs it does **not**
> fire (its `matches` stays below its threshold) while the other rules fire as
> their counts warrant. The verifier recomputes every count from `/app/rules.json`
> and the logs, so any correct rule set with sound thresholds is accepted.

---

## Stage 2 — Symmetric-AES-256 encrypted release archive

Write an executable script `/app/encrypt.sh`. The operator must ship a snapshot of
`/app/logs` as a **GPG symmetric-encrypted** archive.

`/app/encrypt.sh` must:

1. Read the user-provided passphrase file `/app/.vault-pass` (already on disk).
2. Build a **deterministic** plaintext archive of `/app/logs` — e.g. `tar` with
   `--sort=name` and fixed `--mtime`, then `gzip -n` (no timestamp header).
   Put this transient archive **only under `/tmp`**.
3. **Discover** how the tool offers its strongest symmetric option: run
   `man gpg` and identify that `AES-256` is the strongest symmetric block cipher
   listed. Write that name to `/app/best-mode.txt` (content `AES256`; `AES-256` is
   also acceptable).
4. Seal the archive with **exactly AES-256**: symmetric encryption
   `gpg --symmetric --cipher-algo AES256` (batch/pinentry-loopback) and the
   strongest key-stretching (`--s2k-digest-algo SHA512`), writing the ciphertext
   to `/app/archive.gpg`.
5. **Remove every plaintext intermediate** before returning — no `.tar` or
   `.tar.gz` may remain on disk anywhere in `/app` or `/tmp`.

`/app/archive.gpg` must decrypt (with `/app/.vault-pass`) to the original
`/app/logs` contents, byte for byte.

> The verifier independently decrypts `/app/archive.gpg`, confirms the OpenPGP
> packet cipher is **9 (AES-256)**, checks `/app/best-mode.txt` names AES-256, and
> scans `/app` for leftover plaintext archives.

---

## 3 — Cipher-oracle key recovery (hard time budget)

`/app/cipher_service.py` is a local black-box "cipher" oracle (a stand-in for a
symmetric device). Consult it:

- Library: `import cipher_service`; `cipher_service.query("<hex>")` returns the
  hex ciphertext of a hex plaintext.
- Script: `python3 /app/cipher_service.py <hex>` prints the hex ciphertext.

The oracle XORs each plaintext byte with a secret **8-byte key** `K`, repeating
cyclically: `ciphertext[i] = plaintext[i] xor K[i mod 8]`. `K` is fixed for a
given oracle instance but unknown at authoring time.

- **chosen plaintext, bounded work, strict time.** Write `/app/oracle.py` that uses
  the oracle's known plaintext/ciphertext pairs to recover `K` and writes
  `/app/oracle-results.json`:

```json
{ "key": "<16 hex chars>", "key_bytes": 8, "rounds": 4, "elapsed_ms": 1, "ok": true }
```

- Rise to the adversarial case: the verifier resets the oracle's secret to a fresh
  hidden key and re-runs `/app/oracle.py`. You must recover the key from the live
  oracle output (not a fixed constant), and report it all in well under 25 seconds.

*Hint:* an all-zero plaintext block of length ≥ 8 directly folds `K` into the
ciphertext stream.

## 4 — Malicious serialized object (broker message)

Implement the deserialization failure. The queue consumer `/app/worker.py` is a
stock broker worker that does `pickle.load` on a message at `/app/message.pkl`:

```
python3 /app/worker.py <message.pkl>
```

Author `/app/gadget.py` that **crafts a binary-serialized exploit payload** —
a message whose deserialization runs the shell command
`touch /app/pwn-proof.txt` — and writes it to `/app/message.pkl`. Use a
`__reduce__` (or equivalent) gadget that calls `os.system` when loaded.

- Deliver the message through the real `/app/worker.py` once to confirm `K` the
  command's side effect appears as `/app/pwn-proof.txt`.

The verifier deletes `/app/pwn-proof.txt`, then runs `/app/worker.py /app/message.pkl`
in a **fresh process** and requires the marker to reappear — proving the gadget
executes the appended command end to end.

**Forced constraints**

- Never modify the provided `/app/logs/*`, `/app/.vault-pass`,
  `/app/cipher_service.py`, or `/app/worker.py`.
- Everything must be executable from a clean `/app`; the verifier re-runs
  `/app/detect.sh`, `/app/oracle.py`, and `/app/worker.py`.
- Keep the fixed output paths (`/app/alert.json`, `/app/report.json`,
  `/app/archive.gpg`, `/app/best-mode.txt`, `/app/oracle-results.json`,
  `/app/message.pkl`, `/app/pwn-proof.txt`).

When all four stages pass, you are done.
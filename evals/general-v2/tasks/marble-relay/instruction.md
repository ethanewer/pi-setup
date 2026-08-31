# marble-relay — frame-protocol relay service

The Marble logistics platform ships a **frame launcher** at
`/app/launcher.js` (Node.js). It discovers, boots, and drives an external
relay binary over a length-prefixed JSON frame protocol. Your job is to author
that relay binary from scratch and wire it up so the launcher boots it
successfully and every frame exchange matches the contract. The launcher is an
immutable input — **do not modify `/app/launcher.js`**.

## Deliverables (both required)

1. `/app/relay.json` — the launcher manifest. It must be a JSON object whose
   `entry` field is exactly the string `"/app/bin/relay"`. If the manifest is
   missing, invalid, or points anywhere else, the launcher cannot find the
   entrypoint and the boot fails.
2. `/app/bin/relay` — a **native compiled executable** (an ELF binary; a
   `#!/...` script is not acceptable). Author its source yourself (e.g. C,
   compiled with the installed `gcc`) and leave the compiled binary at that
   exact path.

## Launcher protocol

`node /app/launcher.js <case.json>` performs:

1. **Discovery:** read `/app/relay.json`; the `entry` must be exactly
   `"/app/bin/relay"` and must be an existing file, otherwise the launcher
   prints `BOOT_FAIL ...` (exit 3).
2. **Boot handshake:** spawn the entrypoint and send the frame
   `{"type":"hello","proto":1}`. The relay must reply, within 5 seconds, with
   exactly the frame `{"type":"ready","proto":1}`. On success the launcher
   prints `BOOT_OK`.
3. **Query loop:** for each query in the case file it sends one frame and
   expects one reply frame (in order). Matching replies print `FRAME_OK <i>`;
   mismatches or timeouts print `FRAME_FAIL <i> ...`.
4. **Result:** `ALL_OK` (exit 0) when every query matched, else `ALL_FAIL`.

### Frame wire format

Every frame (both directions) is:

```
4-byte big-endian unsigned length N, followed by exactly N bytes of UTF-8 JSON
```

The relay must read frames in full from stdin (handling partial reads), parse
the JSON object, and write each reply as exactly one length-prefixed frame to
stdout (flush before awaiting the next request). Exactly one reply frame per
request, in request order. The relay is a long-running process: it must serve
many frames in one session and must not exit after the first reply.

## Relay behavior contract

Each request is a JSON object. Replies must deep-equal the shapes below
(extra or missing keys count as mismatches; key order does not matter).

### Boot

- Any request with `"type": "hello"` is answered with
  `{"type":"ready","proto":1}`.

### Operations (requests carry an `"op"` field plus operands)

| request | reply |
|---|---|
| `{"op":"sum","values":[ints]}` | `{"type":"result","value":<sum>}` |
| `{"op":"prod","values":[ints]}` | `{"type":"result","value":<product>}` |
| `{"op":"minmax","values":[ints]}` (non-empty) | `{"type":"result","min":<min>,"max":<max>}` |
| `{"op":"uniq","values":[ints]}` | `{"type":"result","values":<ascending distinct ints>}` |
| `{"op":"rev","values":[ints]}` | `{"type":"result","values":<reversed list>}` |
| `{"op":"fnv1a","text":<string>}` | `{"type":"result","value":<unsigned 32-bit FNV-1a of the text's UTF-8 bytes>}` |
| `{"op":"delay","ms":<int 1..300>}` | sleep `ms` milliseconds, then `{"type":"result","value":<ms>}` |

- `sum` of `[]` is `0`; `prod` of `[]` is `1`; `uniq`/`rev` of `[]` are `[]`.
- Integers in `values` may be negative. Sums/products stay within 64-bit range
  for the graded inputs.
- FNV-1a 32-bit: start `hash = 2166136261`; for each byte: `hash ^= byte`,
  then `hash = (hash * 16777619) mod 2^32`. The reply `value` is that unsigned
  integer in decimal. FNV-1a of `""` is `2166136261`.

### Errors

- `values` missing, not an array, containing a non-integer (e.g. `1.5`, a
  string, a boolean), or — for `minmax` — an empty array:
  reply `{"type":"error","code":"bad-value"}`.
- `text` missing or not a string (for `fnv1a`), or `ms` missing / not an
  integer / outside 1..300 (for `delay`): reply
  `{"type":"error","code":"bad-value"}`.
- An unknown `op` (or a request with no `op` field at all, other than the
  boot `hello`): reply `{"type":"error","code":"bad-op"}`.

Error replies never crash the relay: it must keep serving further frames.

## Definition of done

- `node /app/launcher.js` boots your relay (`BOOT_OK`) on every case the
  grader supplies, and every query matches (`FRAME_OK`, `ALL_OK`).
- The grader's hidden cases exercise every operation above, error replies,
  a delayed frame mid-session (proving the relay stays alive across frames),
  and frames whose JSON keys arrive in varying orders — so parse JSON
  properly rather than matching bytes.
- The binary must be a real ELF executable built from your own source (the
  grader checks `file /app/bin/relay` reports ELF).

## Constraints

- Build only with the preinstalled toolchain (`gcc`, `make`); libc only, no
  external libraries (no JSON libraries).
- No network access. Do not modify `/app/launcher.js`.
- Keep both deliverables at the exact paths above.

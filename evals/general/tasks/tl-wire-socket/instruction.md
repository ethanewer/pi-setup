# tl-wire-socket: WebSocket server — opening handshake and frame codec

An embedded gateway device needs a small WebSocket endpoint so browser
clients can open a long-lived connection and exchange short messages. The
container has **only Python's standard library** — no third-party websocket
package is installed, and there is no network to fetch one. You must
implement the **server side of the WebSocket protocol yourself**, in exactly
the documented subset below.

## Environment

- `/app/lib/sockkit.py` — a small, self-authored **blocking TCP server
  skeleton** with a per-connection callback API: `serve(host, port, handler)`
  binds the listener and, per accepted connection, calls
  `handler(sock, addr)` in a fresh thread; when the handler returns the
  socket is closed. **Do not modify this file** — the grader verifies it is
  byte-identical to the shipped copy.
- `/app/config.json` — JSON `{"host": ..., "port": ..., "path": ...}` where
  `path` starts with `/`. Your server must read this file at **startup**
  (port and path must never be hard-coded).
- Python 3.12, standard library only (`socket`, `hashlib`, `base64`,
  `struct`, `json`, ...). Loopback networking only.

## Your deliverable

`/app/ws_server.py` — a program run as `python3 /app/ws_server.py` that:

1. reads `/app/config.json`;
2. binds `host`:`port` (use sockkit's `serve(...)` with a handler that
   implements the protocol);
3. answers the WebSocket opening handshake for the configured `path`;
4. then parses and answers frames per the exact subset below.

Every header and frame is built/parsed by hand from raw bytes. `hashlib` /
`base64` / `struct` are fine; no parsing library exists in the image (and
none is needed for this subset).

## Opening handshake (exact subset)

The client sends:

```
GET <path> HTTP/1.1
Host: <host>
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <base64 of 16 random bytes>
Sec-WebSocket-Version: 13

```

Rules:

- Method **GET**, HTTP version **1.1**, request-target's path (the part
  before any `?`) **must equal** the configured `path`.
- Header names are case-insensitive. `Upgrade` value must be `websocket`
  (case-insensitive) and the `Connection` value must contain the token
  `upgrade` (case-insensitive).
- `Sec-WebSocket-Version` must be `13`.
- `Sec-WebSocket-Key` must be present and base64-decode to exactly 16 bytes.

On success reply exactly (header order irrelevant, values as shown):

```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: <computed>

```

where, with MAGIC = `258EAFA5-E914-47DA-95CA-C5AB0DC85B11`:

```
accept = base64( SHA-1( key_value_string + MAGIC ) )
```

i.e. SHA-1 over the concatenation of the **ASCII bytes of the key value
exactly as received** and the ASCII bytes of MAGIC, then base64 of the
20-byte digest.

Any handshake failure (wrong path, bad method/version, missing or invalid
key, wrong version header, header block larger than 8 KiB, unparseable
request line) must answer `HTTP/1.1 400 Bad Request` and close. An empty
request (bare TCP connect / immediate EOF) must simply close quietly.

## Frame codec (exact subset)

All multibyte integers are network byte order (big-endian).

Byte 1: FIN (bit 7) | RSV1-3 (bits 6–4, must be 0) | opcode (bits 3–0).
Byte 2: MASK (bit 7) | payload length (bits 6–0).

- length ≤ 125 → that value;
- length = 126 → two following bytes hold the 16-bit payload length;
- length = 127 → eight following bytes hold the 64-bit payload length
  (the 64-bit value must be < 2^63, i.e. its first byte ≤ 0x7F).

Lengths must be **minimally encoded**: a 16-bit length < 126, or a 64-bit
length < 65536, is a protocol error.

Opcodes: `0` continuation, `1` text, `2` binary, `8` close, `9` ping,
`10` pong. Any other opcode is reserved.

- **Client→server frames MUST have MASK=1**: the 4-byte masking key follows
  the (extended) length, and each payload byte is XORed: byte `i` becomes
  `payload[i] ^ key[i % 4]`.
- **Server→client frames MUST have MASK=0** (unmasked).

## Server behavior

- **Echo**: every complete text (1) or binary (2) message is echoed back as
  a single unmasked frame with the same opcode and the same payload.
- **Fragmentation**: a message may arrive split as first frame opcode
  text/binary with FIN=0, then zero or more continuation frames (opcode 0)
  with FIN=0, then a final continuation with FIN=1. The server reassembles
  and echoes **one** frame (opcode of the first fragment) carrying the
  concatenated payload. Partial fragments produce **no echo**. A text/binary
  frame starting while a fragmented message is still open, or a continuation
  with no message open, is a protocol error (1002).
- **Control frames** may be interleaved between fragments; they are
  processed immediately, not buffered:
  - ping (9) → reply one pong (10) with the **same payload**, immediately;
  - pong (10) → ignore;
  - control frames must have FIN=1 and payload ≤ 125 bytes.
- **Close (8)**: reply with a close frame carrying the **exact same payload
  (status code + reason)** you received (empty payload → empty payload in
  the reply), discard any in-progress fragments, send nothing further, and
  close the TCP connection.
- **UTF-8**: text messages — including reassembled ones — must be valid
  UTF-8 (strict `bytes.decode("utf-8")`). Invalid text → close code 1007,
  no echo.

## Malformed frames → documented close codes

For each of these the server sends a close frame carrying the code and then
closes the connection (no further frames, then TCP close):

- **1002** protocol error: unmasked client→server frame; any RSV bit set;
  reserved opcode; fragmented control frame (FIN=0); control payload
  > 125 bytes; non-minimal length encoding; 64-bit length with the high bit
  set (≥ 2^63); continuation frame with no message in progress; new
  text/binary frame while a fragmented message is open.
- **1007** invalid payload data: a text message (whole or after
  reassembly) that fails strict UTF-8 decoding.

## How you will be graded

The grader runs `python3 /app/ws_server.py` and talks to it over loopback
with its own **raw-socket WebSocket client** — no third-party client is
involved. It:

- recomputes `Sec-WebSocket-Accept` from each presented key, so a
  canned/fixed response can never pass;
- exercises masked echo round-trips with payload sizes 0, 125, 126, 127,
  65535, 65536 and larger (exercising the 7-bit, 16-bit and 64-bit length
  fields), plus additional random payload batteries;
- tests fragmentation reassembly (including interleaved ping/pong between
  fragments), ping→pong payload echo, close-handshake echo, each
  malformed-frame close-code case above, and the "nothing further after
  close" rule;
- **replaces `/app/config.json` with additional configurations on different
  ports and paths** and repeats the battery — hard-coding the shipped port
  or path fails.

Your server must handle many back-to-back connections and survive
restarts.

## Constraints

- Do not modify `/app/lib/sockkit.py` and do not add packages (none are
  installed, and there is no network).
- Python standard library only; loopback (`127.0.0.1`) only.
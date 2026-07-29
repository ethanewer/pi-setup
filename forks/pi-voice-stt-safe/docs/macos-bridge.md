# Mac microphone bridge

Use this when Pi runs on a VPS but your real microphone is on your Mac. The
`Ctrl+R` UX is unchanged; only audio capture moves to a small daemon on the Mac,
reached through a reverse SSH tunnel. The bridge is **opt-in**: it is only used
when the config sets `capture.type: "bridge"`.

## Architecture

```
Pi on the VPS                       your Mac
┌──────────────────────────┐        ┌──────────────────────────────────┐
│ capture.type "bridge"    │        │ app.pi-voice-stt.bridge          │
│ POST /start /stop /cancel│──ssh──▶│ 127.0.0.1:18765 (loopback only)  │
│ GET  /health             │ tunnel │ AVFoundation or ffmpeg capture    │
└──────────────────────────┘        └──────────────────────────────────┘
```

- The VPS never reaches the Mac directly: `RemoteForward 127.0.0.1:18765` on the
  Mac-initiated SSH connection exposes the daemon on the VPS loopback.
- `/start` begins recording, `/stop` returns the WAV to the VPS (which then
  transcribes it with the configured provider), `/cancel` throws it away.
- Two LaunchAgents keep it running: `app.pi-voice-stt.bridge` (daemon) and
  `app.pi-voice-stt.tunnel` (tunnel).

Two daemon flavors ship in `tools/`:

| Flavor | File | Used when |
| --- | --- | --- |
| Native macOS app | `macos-bridge-native.swift` | `swiftc` is available; records with AVFoundation, so microphone permission is granted to `Pi Voice STT Bridge.app` and no terminal has to stay open |
| Node fallback | `macos-bridge-server.mjs` | no `swiftc`; records with `ffmpeg -f avfoundation` and inherits microphone permission from whatever launched it (Terminal/cmux) |

## Prerequisites

- macOS with an SSH alias for the VPS in `~/.ssh/config` (with `HostName`).
- `node` and `ffmpeg` on the Mac (`PI_STT_BRIDGE_NODE` / `PI_STT_BRIDGE_FFMPEG`
  override the binaries used).
- `swiftc` (Xcode command line tools) for the native app; optional.
- Key-based SSH from the Mac to the VPS (the tunnel runs unattended).

## Install

On the **Mac**:

```bash
tools/install-macos-bridge.sh my-vps
```

This installs the daemon under `~/.local/share/pi-voice-stt-bridge/`, generates
`~/.config/pi-voice-stt-bridge/token` (chmod 600), builds
`~/Applications/Pi Voice STT Bridge.app` when `swiftc` is present, writes both
LaunchAgents, and appends a `<vps>-voice-tunnel` SSH host with `RemoteForward`.
See the header of `tools/install-macos-bridge.sh` for the environment overrides.

Copy the token to the **VPS**:

```bash
scp ~/.config/pi-voice-stt-bridge/token my-vps:~/.pi/agent/pi-voice-stt-bridge.token
```

Point Pi at the bridge on the VPS (e.g. `~/.pi/agent/stt.json`):

```json
{
  "capture": {
    "type": "bridge",
    "endpoint": "http://127.0.0.1:18765",
    "tokenFile": "~/.pi/agent/pi-voice-stt-bridge.token",
    "requestTimeoutSeconds": 30,
    "maxSeconds": 120,
    "minBytes": 4096
  },
  "provider": {
    "type": "groq",
    "model": "whisper-large-v3-turbo",
    "apiKeyEnv": "GROQ_API_KEY",
    "language": "fr"
  }
}
```

Then run `/stt doctor` in Pi: it reports `bridge http://127.0.0.1:18765` when the
health check succeeds.

## Security model

- **A token is mandatory.** The daemon can switch the microphone on, so it
  refuses to start without `PI_STT_BRIDGE_TOKEN` or a non-empty
  `PI_STT_BRIDGE_TOKEN_FILE`, and every endpoint (including `/health`) requires
  `Authorization: Bearer <token>`. Without it, any local process — or any web
  page able to send a CORS simple request to `127.0.0.1` — could start a
  recording.
- **Loopback by default.** `PI_STT_BRIDGE_HOST` still selects the bind address,
  but a non-loopback value is refused unless `PI_STT_BRIDGE_ALLOW_REMOTE=1` is
  set as well. The supported path to a remote Pi is the SSH tunnel, which needs
  no LAN exposure. The native daemon judges the address it actually binds, so it
  takes an IPv4 address (any `127.0.0.0/8` address counts as loopback) or the
  names `localhost` / `::1`, and refuses anything else it cannot parse.
  `capture.endpoint` on the Pi side enforces the same range, so a bridge reached
  over plain `http` may use any `127.0.0.0/8` address, `localhost` (trailing dot
  included), `::1` in any spelling, or IPv4-mapped loopback such as
  `::ffff:127.0.0.1` — and nothing outside it. A bridge somewhere else has to be
  reached over `https`.
- **Tokens are compared in constant time** in both daemons, so a wrong token
  cannot be recovered byte by byte from response timing.
- The token file is `chmod 600`, and the copy on the VPS should be too.
- Rotate the token by writing a new value into the file on both machines and
  restarting the daemon
  (`launchctl kickstart -k gui/$(id -u)/app.pi-voice-stt.bridge`).
- Recording only happens between `/start` and `/stop`; the daemon also stops on
  its own after `PI_STT_BRIDGE_MAX_SECONDS` (default 120).

## Daemon environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `PI_STT_BRIDGE_HOST` | `127.0.0.1` | bind address, IPv4 or `localhost` (non-loopback needs `PI_STT_BRIDGE_ALLOW_REMOTE=1`) |
| `PI_STT_BRIDGE_ALLOW_REMOTE` | unset | set to `1` to allow a non-loopback bind on purpose |
| `PI_STT_BRIDGE_PORT` | `18765` | bind port |
| `PI_STT_BRIDGE_TOKEN` | unset | bearer token (required, unless a token file is used) |
| `PI_STT_BRIDGE_TOKEN_FILE` | `~/.config/pi-voice-stt-bridge/token` (native) | file holding the bearer token |
| `PI_STT_BRIDGE_FFMPEG` | `ffmpeg` | ffmpeg binary (Node fallback only) |
| `PI_STT_BRIDGE_INPUT_FORMAT` | `avfoundation` | ffmpeg input format (Node fallback only) |
| `PI_STT_BRIDGE_INPUT` | `:0` | ffmpeg input device (Node fallback only) |
| `PI_STT_BRIDGE_SAMPLE_RATE` | `16000` | capture sample rate |
| `PI_STT_BRIDGE_CHANNELS` | `1` | capture channels |
| `PI_STT_BRIDGE_MIN_BYTES` | `4096` | reject recordings smaller than this |
| `PI_STT_BRIDGE_MAX_SECONDS` | `120` | hard stop for a single recording |

## Troubleshooting

- **`/stt doctor` reports 401** — the VPS token does not match the Mac token.
  Re-copy `~/.config/pi-voice-stt-bridge/token` and check `capture.tokenFile`.
- **`/stt doctor` cannot connect** — the tunnel is down. On the Mac:
  `launchctl kickstart -k gui/$(id -u)/app.pi-voice-stt.tunnel`, then check
  `~/Library/Logs/pi-voice-stt-tunnel.err.log`. A stale sshd listener on the VPS
  is cleaned up by `tunnel.sh` on each start.
- **Daemon exits immediately** — check
  `~/Library/Logs/pi-voice-stt-bridge.err.log`: a missing token and a refused
  non-loopback bind are both logged there.
- **"Bridge recording is silent"** — microphone permission. With the native app,
  allow *Pi Voice STT Bridge* under System Settings → Privacy & Security →
  Microphone; with the Node fallback, grant it to the app that launched the
  daemon (Terminal/cmux) and make sure `PI_STT_BRIDGE_INPUT` names a real device
  (`ffmpeg -f avfoundation -list_devices true -i ""`).
- **"recording already active"** — a previous `/start` was never stopped; send
  `/cancel` (Esc in Pi) or restart the daemon.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/app.pi-voice-stt.bridge.plist 2>/dev/null
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/app.pi-voice-stt.tunnel.plist 2>/dev/null
rm -rf ~/.local/share/pi-voice-stt-bridge ~/.config/pi-voice-stt-bridge \
       ~/Library/LaunchAgents/app.pi-voice-stt.{bridge,tunnel}.plist \
       ~/Applications/"Pi Voice STT Bridge.app"
```

Then remove the `<vps>-voice-tunnel` block from `~/.ssh/config` if you no longer
need it, and drop `capture.type: "bridge"` from the config on the VPS.

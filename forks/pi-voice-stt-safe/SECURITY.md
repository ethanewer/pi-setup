# Security Policy

Pi extensions run with the same permissions as your user account. Review code before installing any Pi package.

## Secrets

Pi Voice STT never intentionally writes API keys to session history. Prefer environment variables or macOS Keychain for secrets. Do not commit config files containing `apiKey`.

A resolved key must look like a credential (single line, no whitespace, at most 4096 characters), so `apiKeyEnv` / `apiKeyFile` cannot turn an unrelated variable or file into a `Bearer` header. The `OPENAI_API_KEY` default (`provider` for `openai-compatible`/`local`, and `cleanup`) applies to OpenAI endpoints only — plus any host you list yourself in `PI_STT_ALLOWED_ENDPOINT_HOSTS`, which counts as that vendor on purpose and lives outside the config file for exactly that reason. Any other host has to name its own credential, or name none at all with `apiKeyEnv: ""`. A loopback endpoint is treated as keyless on `http` and `https` alike: it gets no defaulted key and needs none. A key it names itself is still sent over `https`; over plain `http` the request carries no `Authorization` header at all, so a local server that insists on a key has to be reached over `https`.

## Endpoint policy

Non-local transcription endpoints must use HTTPS. Plain HTTP is accepted only for loopback hosts — `localhost` (with or without a trailing dot), any address in `127.0.0.0/8`, `::1` in any spelling, and IPv4-mapped loopback such as `::ffff:127.0.0.1` — to support local STT servers and the Mac bridge. Hosts that merely look local (`localhost.evil.com`, `127.0.0.1.evil.com`) and the `0.0.0.0` wildcard are not loopback. The decision is made on the hostname after URL parsing has normalized it, so shorthand literals that parse to a loopback address (`http://127.1/` and `http://0x7f000001/` both become `http://127.0.0.1/`) count as loopback as well. The bridge daemon judges its own bind address by the same `127.0.0.0/8` rule, except that a bind address has to be an IP literal or the name `localhost` / `::1` — it is never resolved through DNS. See [docs/macos-bridge.md](docs/macos-bridge.md).

Named vendor providers (`openai`, `groq`, `mistral`, `deepgram`, `elevenlabs`, `gladia`, `assemblyai`) inject that vendor's key, so their endpoint is pinned to the vendor's own domain unless the host is listed in `PI_STT_ALLOWED_ENDPOINT_HOSTS`. The `openai-compatible` and `local` types remain the escape hatch for arbitrary hosts: they send the recorded audio wherever `endpoint` points, but they never carry a defaulted `OPENAI_API_KEY` there unless that host is listed in `PI_STT_ALLOWED_ENDPOINT_HOSTS`. For `openai-compatible`, a host that is neither OpenAI's nor loopback must name the secret it receives (`apiKeyEnv`, `apiKeyFile`, `keychainService`, or `apiKeyEnv: ""` for a keyless server) or loading fails; a loopback endpoint needs nothing, since it cannot hand a credential to a third party.

`local` means a server on this machine and defaults to no credential at all, so an `endpoint` off loopback is refused until the config says it is meant: name the credential that host receives, or `apiKeyEnv: ""` to keep sending it audio with none. The capability is intact — it just has to be written down, because `local` pointed at a remote host would otherwise ship the microphone off the machine under a type named for staying on it. Review these fields whenever a config file was not written by you.

## Mac microphone bridge

The bridge daemon refuses to start without a bearer token and requires it on every request, and it only binds a non-loopback address when `PI_STT_BRIDGE_ALLOW_REMOTE=1` is set explicitly. See [docs/macos-bridge.md](docs/macos-bridge.md).

## Reporting issues

Please report security issues privately if possible. If private reporting is not available, open a minimal public issue without credentials or sensitive logs.

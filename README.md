# Ethan's Pi setup

A reproducible, fast [Pi coding agent](https://pi.dev) setup with two entrypoints:

- **`pi`** — full environment with Voice STT, native browser automation, and dynamic workflows.
- **`p`** — lean environment with Voice STT only, quiet startup, no skills, and a smaller system prompt.

Both commands run the same Pi installation through Pi's Bun entrypoint. They share authentication, model catalogs, sessions, helper binaries, and installed package files.

## Install

On a fresh macOS or Linux machine, run:

```bash
curl -fsSL https://raw.githubusercontent.com/ethanewer/pi-setup/main/install.sh | bash
```

Open a new terminal afterward. The installer is idempotent and preserves unrelated existing Pi packages and settings.

> Review [`install.sh`](install.sh) before piping it to a shell if you do not trust remote scripts. The installer does not copy credentials or API keys.

## Requirements

- macOS or Linux, x86-64 or ARM64
- `curl`
- `OPENAI_API_KEY` for the configured Pi model and OpenAI transcription
- `ffmpeg` plus microphone permission for Voice STT

The installer installs Bun, Pi, the pinned extensions, `agent-browser`, and its Chrome runtime. It warns rather than failing if Chrome or `ffmpeg` setup needs manual attention.

### Tested platforms

The one-line installer has been tested in isolated homes on:

- macOS on Apple Silicon
- two Ubuntu 22.04 x86-64 servers

The Linux validation included installing Chrome and an `agent-browser` open/title/close smoke test against `https://example.com`.

## Installed versions

| Component | Version |
|---|---:|
| `@earendil-works/pi-coding-agent` | `0.81.1` |
| `pi-voice-stt` | `0.4.0` |
| `pi-agent-browser-native` | `0.2.71` |
| `@quintinshaw/pi-dynamic-workflows` | `3.4.1` |
| `agent-browser` | `0.32.2` |

## Entrypoints

### `pi`: full environment

`pi` loads the normal package configuration:

- built-in `read`, `bash`, `edit`, and `write` tools
- Voice STT
- `agent_browser`
- `workflow` and `workflow_control`
- workflow authoring and built-in workflow skills
- project `AGENTS.md` / `CLAUDE.md` context
- visible startup resource listing

### `p`: lean environment

`p` invokes the same Pi and package installation with:

```text
--no-extensions --no-skills
```

It explicitly reloads only Voice STT and a tiny local extension that removes Pi's documentation block from the system prompt. It also:

- uses quiet startup
- skips the Pi version check
- shares the main session directory
- shares auth, model catalogs, and helper binaries

`p` uses a small settings overlay at `~/.pi/agent-p/settings.json`; it is a configuration profile, not another Pi installation.

## Voice STT

Voice dictation is configured for OpenAI:

```json
{
  "keybind": "alt+p",
  "provider": {
    "type": "openai",
    "model": "gpt-4o-mini-transcribe",
    "apiKeyEnv": "OPENAI_API_KEY",
    "language": "auto"
  }
}
```

Use **Option+P** on macOS or **Alt+P** on Linux to start and stop recording. Press Enter while recording to transcribe and submit, or Escape to cancel.

The API key is read from the environment and is never written into the repository or Pi configuration.

## Performance

Measured warm startup to the beginning of an agent turn on Apple Silicon:

| Configuration | Node | Bun |
|---|---:|---:|
| Full `pi` | 0.780 s | **0.522 s** |
| Lean `p` | 0.412 s | **0.304 s** |

Qwen3.6 prompt-token comparison for a browser/workflow request:

| Configuration | Plain system prompt | Rendered with tool schemas |
|---|---:|---:|
| Base Pi | 558 | 1,475 |
| `p` | **287** | **1,205** |
| Full `pi` | 1,678 | 8,666 |

Actual timing and tokenization vary by machine, working directory, model template, extensions, and request. Workflow arming text injected into the user message is not included in the token table.

## Files created

```text
~/.local/bin/pi                              Bun-backed full entrypoint
~/.local/bin/p                               Lean entrypoint
~/.local/bin/agent-browser                   Bun-backed agent-browser entrypoint
~/.pi/agent/settings.json                    Main Pi settings
~/.pi/agent/stt.json                         Voice STT configuration
~/.pi/agent/npm/                             Shared extension packages
~/.pi/agent/p/remove-pi-documentation.js     Lean prompt filter
~/.pi/agent-p/settings.json                  Quiet lean settings overlay
~/.pi/agent-p/auth.json                      Symlink to main auth
~/.pi/agent-p/models-store.json              Symlink to main model catalog
~/.pi/agent-p/bin                            Symlink to main helper binaries
```

The installer adds `~/.local/bin` and `~/.bun/bin` to `.zshrc` and `.bashrc`.

## Updating

The wrappers locate the installed Pi package dynamically, so reinstalling/updating the package does not require wrapper changes. This repository intentionally pins known-working versions. To upgrade the whole setup, update the version constants in `install.sh`, test on macOS and Linux, and rerun the installer.

## Session archives

Session archives are intentionally excluded. To archive sessions older than 30 days, preserve paths inside the archive and verify it before deleting originals. Authentication files, model credentials, session transcripts, SSH material, and API keys must never be committed here.

## Security

The installed Pi extensions execute with the user's full permissions. Review the packages and this installer before use. Browser profiles and authenticated page contents may become model-visible when browser automation is explicitly configured to use them.

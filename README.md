# Ethan's Pi setup

A reproducible, fast [Pi coding agent](https://pi.dev) setup with two entrypoints:

- **`pi`** — full environment with Voice STT, native browser automation, dynamic
  workflows, compaction handoff briefs, and background process monitoring.
- **`p`** — lean environment with Voice STT only, quiet startup, no skills, and a
  smaller system prompt.

Both commands run the same Pi installation through Pi's Bun entrypoint. They share
authentication, model catalogs, sessions, helper binaries, and installed package files.

Every extension is installed from `forks/` as a **security-hardened local fork**, not
from npm. See [Extensions are hardened forks](#extensions-are-hardened-forks) and
[`docs/AUDIT.md`](docs/AUDIT.md).

## Install

On a fresh macOS or Linux machine, run:

```bash
curl -fsSL https://raw.githubusercontent.com/ethanewer/pi-setup/main/install.sh | bash
```

Open a new terminal afterward. The installer is idempotent and preserves unrelated
existing Pi packages and settings.

> Review [`install.sh`](install.sh) before piping it to a shell if you do not trust
> remote scripts. The installer does not copy credentials or API keys.

## Requirements

- macOS or Linux, x86-64 or ARM64
- `curl` and `git`
- `OPENAI_API_KEY` for the configured Pi model and OpenAI transcription
- `ffmpeg` plus microphone permission for Voice STT

The installer installs Bun, Pi, the hardened extension forks, `agent-browser`, and its
Chrome runtime. It warns rather than failing if Chrome or `ffmpeg` setup needs manual
attention.

### Tested platforms

The one-line installer has been tested in isolated homes on:

- macOS on Apple Silicon
- two Ubuntu 22.04 x86-64 servers

The Linux validation included installing Chrome and an `agent-browser` open/title/close
smoke test against `https://example.com`.

## Installed versions

| Component | Version |
|---|---:|
| `@earendil-works/pi-coding-agent` | `0.82.0` |
| `agent-browser` | `0.32.2` |

Extension forks and the upstream releases they are based on:

| Fork (Pi local package) | Upstream | Upstream version |
|---|---|---:|
| `pi-voice-stt-safe` | `pi-voice-stt` | `0.4.0` |
| `pi-agent-browser-native-safe` | `pi-agent-browser-native` | `0.2.71` |
| `pi-dynamic-workflows-safe` | `@quintinshaw/pi-dynamic-workflows` | `3.4.1` |
| `pi-process-monitor-safe` | `pi-process-monitor` | hand-written rewrite |
| `pi-context-handoff` | — | first-party |

`vendor.json` is the machine-readable version of this table and is what the tooling
reads.

## Extensions are hardened forks

Pi extensions run in the agent's process with the user's full permissions, so an
extension is part of the trusted computing base. A 2026-07-28 audit of the four upstream
packages found real problems in all of them, including a zero-click remote code execution
path reachable from merely cloning a repository. None of the packages is malicious; the
recurring defect is that they treat project-local files as trusted input.

[`docs/AUDIT.md`](docs/AUDIT.md) records every finding with file and line references.
[`docs/FORKS.md`](docs/FORKS.md) records what each fork changes, and the residual risk
that remains after the fixes. [`docs/LONG_RUNS.md`](docs/LONG_RUNS.md) covers running
autonomously for a long time without stopping — what used to break, what fixed it, and
what can still stop a run.

### Why forks rather than patches applied at install time

`install.sh` regenerates `~/.pi/agent/npm/package.json` and runs `bun install`, and Pi's
own package manager can reinstall or update npm packages at any time. Anything patched in
place under `node_modules` is silently reverted the next time that happens — an
unacceptable failure mode for security fixes, because nothing would signal that the
protection is gone.

Pi never rewrites `local/` packages. Installing the forks as local packages means the
fixes cannot disappear without a change to this repository. It is also the mechanism Pi
documents for custom extensions, and the one `pi-process-monitor-safe` already used.

The trade-off is that upstream upgrades are a deliberate step rather than automatic.
`patches/` and `bin/pi-setup-vendor` make that step mechanical, and
`bin/pi-setup-doctor` reports when a fork has fallen behind upstream.

### Layout

```text
forks/<name>-safe/          The hardened package Pi loads, vendored in full
patches/<pkg>@<ver>.patch   Diff of the fork against pristine upstream
vendor.json                 Which upstream release each fork is based on
bin/pi-setup-doctor         Verify the installed setup matches this repository
bin/pi-setup-vendor         Regenerate patches, or re-vendor onto a new upstream release
docs/AUDIT.md               Every finding, with file and line references
docs/FORKS.md               What each fork changes, and residual risk
```

Git history is arranged so the hardening is reviewable: upstream sources were committed
byte-identical to the published npm tarballs first, so `git log -p -- forks/<name>-safe`
shows exactly what changed and nothing else. `patches/` carries the same information as
standalone diffs.

## Entrypoints

### `pi`: full environment

`pi` loads the normal package configuration:

- built-in `read`, `bash`, `edit`, and `write` tools
- Voice STT
- `agent_browser`
- `workflow` and `workflow_control`
- workflow authoring and built-in workflow skills
- compaction handoff briefs that keep a long run going
- background process monitoring (`monitor`, `/watch`)
- project `AGENTS.md` / `CLAUDE.md` context
- visible startup resource listing

### `p`: lean environment

`p` invokes the same Pi and package installation with:

```text
--no-extensions --no-skills
```

It explicitly reloads only Voice STT and a tiny local extension that removes Pi's
documentation block from the system prompt. It also:

- uses quiet startup
- skips the Pi version check
- shares the main session directory
- shares auth, model catalogs, and helper binaries

`p` uses a small settings overlay at `~/.pi/agent-p/settings.json`; it is a configuration
profile, not another Pi installation. The `pi` wrapper explicitly rejects an inherited
lean-profile environment, so a tmux server started from `p` cannot accidentally turn later
`pi` sessions into the lean configuration.

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

Use **Option+P** on macOS or **Alt+P** on Linux to start and stop recording. Press Enter
while recording to transcribe and submit, or Escape to cancel.

The API key is read from the environment and is never written into the repository or Pi
configuration. `~/.pi/agent/stt.json` is kept mode `600`: the fork re-reads it on every
dictation, and it selects both the transcription host and the capture binary.

In the fork, a named provider type is pinned to that vendor's host. A custom endpoint is
still fully supported — use `"type": "openai-compatible"` (or `"local"`), which is the
documented way to point at your own server.

## Maintenance

### Check the installed setup

```bash
bin/pi-setup-doctor
```

Verifies that every fork in `forks/` matches the copy installed under
`~/.pi/agent/local/`, that Pi's settings load the forks and not the unpatched npm
packages, that `stt.json` is owner-only, and that `trust.json` has no home-wide entry.
Also reports when upstream has published a newer release than a fork is based on. Exits
non-zero on problems, so it can gate CI.

### Change a fork

Edit `forks/<name>-safe/` directly, then:

```bash
bin/pi-setup-vendor --regenerate-patch <name>-safe   # keep the patch in sync
./install.sh                                         # reinstall
bin/pi-setup-doctor                                  # verify
```

`bin/pi-setup-vendor --verify <name>-safe` checks that applying the patch to pristine
upstream reproduces the fork byte for byte.

### Move a fork to a newer upstream release

```bash
bin/pi-setup-vendor <name>-safe <new-version>
```

This downloads the new upstream release, applies the fork's patch, and replaces
`forks/<name>-safe/` on success. If a hunk is rejected it stops and leaves the partially
patched tree with `.rej` files, along with the commands to finish by hand. Afterwards,
re-read the upstream changelog for anything that affects the hardening, reinstall, run
the doctor, and update the version table above.

### Upgrade Pi itself

Update `PI_VERSION` in `install.sh`, test on macOS and Linux, and rerun the installer.
The wrappers locate the installed Pi package dynamically, so they need no changes.
`pi-context-handoff` uses only Pi's public API (`compact`, and the
`session_before_compact` hook), so a Pi upgrade should not disturb it. If Pi ever changes
that hook's contract the extension degrades to native compaction rather than failing.

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

Actual timing and tokenization vary by machine, working directory, model template,
extensions, and request. Workflow arming text injected into the user message is not
included in the token table. These numbers predate the continuation and monitor
extensions being added to the full profile.

## Files created

```text
~/.local/bin/pi                              Bun-backed full entrypoint
~/.local/bin/p                               Lean entrypoint
~/.local/bin/agent-browser                   Bun-backed agent-browser entrypoint
~/.local/bin/pi-agent-browser-config         Browser config CLI
~/.local/bin/pi-agent-browser-doctor         Browser diagnostics CLI
~/.pi/agent/settings.json                    Main Pi settings
~/.pi/agent/stt.json                         Voice STT configuration (mode 600)
~/.pi/agent/local/                           Hardened extension forks
~/.pi/agent/npm/                             Shared extension packages (no longer used
                                             by this setup; pruned on install)
~/.pi/agent/setup-src/                       Clone of this repository, when the
                                             installer is piped from curl
~/.pi/agent/p/remove-pi-documentation.js     Lean prompt filter
~/.pi/agent-p/settings.json                  Quiet lean settings overlay
~/.pi/agent-p/auth.json                      Symlink to main auth
~/.pi/agent-p/models-store.json              Symlink to main model catalog
~/.pi/agent-p/bin                            Symlink to main helper binaries
```

The installer adds `~/.local/bin` and `~/.bun/bin` to `.zshrc` and `.bashrc`.

## Session archives

Session archives are intentionally excluded. To archive sessions older than 30 days,
preserve paths inside the archive and verify it before deleting originals.
Authentication files, model credentials, session transcripts, SSH material, and API keys
must never be committed here.

## Security

The installed Pi extensions execute with the user's full permissions. The forks in this
repository fix the findings in [`docs/AUDIT.md`](docs/AUDIT.md), but they are hardening,
not a sandbox — [`docs/FORKS.md`](docs/FORKS.md) states the residual risk for each one
explicitly. Review the forks and this installer before use.

Two configuration notes that materially affect exposure:

- **Keep `trust.json` narrow.** Pi inherits project trust down the directory tree, so a
  single `"$HOME": true` entry trusts every repository anywhere under your home
  directory without a prompt. Prefer per-repository entries. `bin/pi-setup-doctor`
  flags this.
- **Browser profiles and authenticated page contents may become model-visible** when
  browser automation is explicitly configured to use them.

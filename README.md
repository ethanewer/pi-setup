# Ethan's Pi setup

A reproducible, fast [Pi coding agent](https://pi.dev) setup with two entrypoints:

- **`pi`** — full environment with Voice STT, native browser automation, dynamic
  workflows, compaction handoff briefs, background process monitoring, and `/btw` side
  questions.
- **`p`** — lean environment with Voice STT, `/btw` side questions, and compaction
  handoff briefs, but no browser, monitor, workflows, or skills.

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
| `@earendil-works/pi-coding-agent` | `0.83.0` |
| `agent-browser` | `0.33.1` |

Extension forks and the upstream releases they are based on:

| Fork (Pi local package) | Upstream | Upstream version |
|---|---|---:|
| `pi-voice-stt-safe` | `pi-voice-stt` | `0.4.0` |
| `pi-agent-browser-native-safe` | `pi-agent-browser-native` | `0.2.72` |
| `pi-dynamic-workflows-safe` | `@quintinshaw/pi-dynamic-workflows` | `3.5.0` |
| `pi-process-monitor-safe` | `pi-process-monitor` | rewrite, reviewed vs `1.3.0` |
| `pi-context-handoff` | — | first-party |
| `pi-btw-side` | — | first-party |
| `pi-setup-maintenance` | — | first-party, skills only |

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
- the `update-pi-setup` maintenance skill
- compaction handoff briefs that keep a long run going
- background process monitoring (`monitor`, `/watch`)
- side questions in an ephemeral fork (`/btw`, escape to return)
- project `AGENTS.md` / `CLAUDE.md` context
- visible startup resource listing

### `p`: lean environment

`p` invokes the same Pi and package installation with:

```text
--no-extensions --no-skills
```

It explicitly reloads only Voice STT, `/btw`, compaction handoff briefs, and a tiny
local extension that removes Pi's documentation block from the system prompt. The exact
allowlist keeps the heavier browser, monitor, and workflow extensions out. It also:

- uses quiet startup
- skips the Pi version check
- shares the main session directory
- shares auth, model catalogs, and helper binaries

`p` uses a small settings overlay at `~/.pi/agent-p/settings.json`; it is a configuration
profile, not another Pi installation. The `pi` wrapper explicitly rejects an inherited
lean-profile environment, so a tmux server started from `p` cannot accidentally turn later
`pi` sessions into the lean configuration.

## Side questions (`/btw`)

`/btw <question>` switches the screen to a clean side conversation in an ephemeral fork.
The model sees the history so far as reference context; neither the question nor the
answer enters the main thread's context. The main thread does not have to be idle — it
keeps running behind the view, which is the case `/btw` is for.

```text
/btw does this migration drop data if it runs twice?   ask (screen switches to the fork)
                                                        typing goes to the fork, no prefix
esc                                                     discard it and return
```

The side thread gets read-only tools by default. See
[`forks/pi-btw-side/README.md`](forks/pi-btw-side/README.md) for configuration and for
what does and does not match Codex's `/side`.

## Keybindings

Default tmux only forwards legacy terminal encodings, so several of Pi's defaults never
arrive — `shift+enter` among them. `config/keybindings.json` remaps those, and
[`docs/KEYBINDINGS.md`](docs/KEYBINDINGS.md) records what was measured and why.

| | |
|---|---|
| Newline | `Option+Enter`, or `Ctrl+J` with no terminal setup |
| Queue a follow-up | `Option+Tab` |
| Restore queued messages | `Ctrl+Option+U` |
| Voice dictation | `Option+P`, or the `π` it composes |

The Option bindings need Option to act as Meta — Terminal.app's *Use Option as Meta key*,
iTerm2's *Esc+* for both Left and Right Option. Voice works either way, because the fork
binds the literal `π` as well.

`/hotkeys` lists all of these, including the voice key and what the other keys do while
recording. Check any individual key with `bin/pi-setup-keyprobe`, inside tmux and outside
it.

## Voice STT

Voice dictation is configured for OpenAI:

```json
{
  "keybind": ["alt+p", "π"],
  "provider": {
    "type": "openai",
    "model": "gpt-4o-mini-transcribe",
    "apiKeyEnv": "OPENAI_API_KEY",
    "language": "auto"
  }
}
```

Use **Option+P** on macOS or **Alt+P** on Linux to start recording. The text cursor
becomes `[● recording]`, a slowly pulsing red dot in a grey bracketed block — the input
box itself does not change colour, and nothing is announced in a banner. Mid-text, where
there is no blank space to write into, it is the dot alone. It gives way to
`[⠏ transcribing]` in the same grey when the provider takes over.

What you press next decides where the transcript goes:

| While recording | |
|---|---|
| `Option+P` again | keep it in the input box |
| `Enter` | send it |
| `Option+Tab` | queue it as a follow-up |
| `Escape` | throw the recording away |
| anything else | keep it in the box, then apply that key |

Transcription never blocks you. The moment recording stops, a `[⠏ transcribing]`
placeholder takes the transcript's place and you keep typing. When the provider answers,
the placeholder becomes the text.

Sending and queueing take **the whole message**, not just the speech: anything already
typed leaves the composer with it, and the placeholder holds the spot where the cursor
was, so `typed words [⠏ transcribing] more` is sent as one message once the transcript
lands. If transcription fails, the message becomes an error, **nothing is sent**, and the
text goes back into the composer. The model receives a spoken message only once the
transcript exists.

`stt.json` takes a list, so the same chord works whether or not the terminal treats Option
as Meta: `"keybind": ["alt+p", "π"]`. Pi's own keybindings cannot express the literal
character — `matchesKey("π", "π")` is false — which is why this lives in the fork.

The API key is read from the environment and is never written into the repository or Pi
configuration. `~/.pi/agent/stt.json` is kept mode `600`: the fork re-reads it on every
dictation, and it selects both the transcription host and the capture binary.

In the fork, a named provider type is pinned to that vendor's host. A custom endpoint is
still fully supported — use `"type": "openai-compatible"` (or `"local"`), which is the
documented way to point at your own server.

## Maintenance

The whole procedure — updating Pi, updating a fork onto a newer upstream, what to
re-review afterwards, and how to roll back — is also a Pi skill, `update-pi-setup`, so an
agent asked to "update pi" follows the pinned path instead of reaching for `pi update`.
Read it at
[`forks/pi-setup-maintenance/skills/update-pi-setup/SKILL.md`](forks/pi-setup-maintenance/skills/update-pi-setup/SKILL.md)
or invoke it with `/skill:update-pi-setup`.

> Do not run `pi update` or `bun add --global` for Pi or the extensions. `install.sh`
> pins both versions and rewrites the wrappers; anything installed around it is reverted
> by the next run and reported as drift by `bin/pi-setup-doctor`.

### Check the installed setup

```bash
bin/pi-setup-doctor
```

Verifies that every fork in `forks/` matches the copy installed under
`~/.pi/agent/local/`, that Pi's settings load the forks and not the unpatched npm
packages, that `stt.json` is owner-only, that `trust.json` has no home-wide entry, and
that the installed Pi and `agent-browser` match the versions `install.sh` pins, and that
`pi-dynamic-workflows-safe`'s `dist/` still mirrors its `src/` — the package exports reach
both, so a stale `dist` would export code nobody audited. Also reports when npm has
published a newer release than this repository pins, for Pi, `agent-browser`, or a fork's
upstream. Exits non-zero on problems, so it can gate CI.

### Run the tests

```bash
bun test tests/       # pure logic, no network or model
tests/fork-suites.sh  # the suites that ship inside the forks
tests/smoke.sh        # installed setup: tools, bash, /btw, browser, workflow
tests/tui-btw.sh      # TUI-only: the full-screen /btw view, the main thread behind it, escape (needs tmux)
tests/linux-install.sh # the published install.sh on a clean Ubuntu container (needs Docker)
```

`bun test tests/` covers the pure logic of the first-party extensions: the history
sanitizer that keeps a mid-turn `/btw` snapshot valid, prompt assembly and config parsing,
the voice keybind matcher and its placeholder/cursor rendering, and the compaction file-list
carry-forward. The two scripts drive the installed setup with real model calls; `tests/smoke.sh
--quick` skips the browser and workflow runs.

Scope the command to `tests/`. A bare `bun test` also collects
`forks/pi-process-monitor-safe/test/`, which is that fork's own suite; run it with
`tests/fork-suites.sh` instead. That script borrows the dev dependencies the suite needs
from Bun's global tree — Pi already depends on all of them — so it needs no download and
leaves nothing behind. Without it the suite does not run at all: 84 tests across 12 files
that look like coverage and provide none.

`tests/linux-install.sh` is the only thing here that does not run on macOS. It pipes the
*published* `install.sh` into a clean `ubuntu:24.04` container as a non-root user, so
commit and push before running it. It checks that a missing `unzip` is refused at the
door rather than halfway through, that the install completes, and that
`bin/pi-setup-doctor` exits 0 on a machine with no `node` at all. Pass an image and a git
ref to test something else: `tests/linux-install.sh debian:12 my-branch`.

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
included in the token table. The `p` measurements predate `/btw` and context handoff being
added to that profile; the full-profile measurements predate context handoff and monitor.

## Files created

```text
~/.local/bin/pi                              Bun-backed full entrypoint (only one)
~/.local/bin/p                               Lean entrypoint
~/.local/bin/agent-browser                   Bun-backed agent-browser entrypoint
~/.local/bin/pi-agent-browser-config         Browser config CLI
~/.local/bin/pi-agent-browser-doctor         Browser diagnostics CLI
~/.pi/agent/settings.json                    Main Pi settings
~/.pi/agent/stt.json                         Voice STT configuration (mode 600)
~/.pi/agent/keybindings.json                 Keys remapped for tmux and Kitty terminals
~/.pi/agent/local/                           Hardened extension forks
~/.pi/agent/npm/                             Shared extension packages (no longer used
                                             by this setup; pruned on install)
~/.pi/agent/setup-src/                       Clone of this repository, when the
                                             installer is piped from curl
~/.pi/agent/p/remove-pi-documentation.js     Lean prompt filter
~/.pi/agent-p/settings.json                  Quiet lean settings overlay
~/.pi/agent-p/keybindings.json               The same remapped keys for the lean profile
~/.pi/agent-p/auth.json                      Symlink to main auth
~/.pi/agent-p/models-store.json              Symlink to main model catalog
~/.pi/agent-p/bin                            Symlink to main helper binaries
```

The installer adds `~/.local/bin` and `~/.bun/bin` to `.zshrc` and `.bashrc`.

There is exactly one entrypoint per command. Pi is installed once, globally, by Bun;
`bun add --global` also links its own `pi` and `agent-browser` shims into `~/.bun/bin`,
and the installer removes them. Those shims point at the same installation but bypass the
wrappers above — notably `pi`'s guard against inheriting the lean `p` profile from a tmux
server. If you previously installed Pi another way (npm global, Homebrew), remove it:
`npm uninstall -g @earendil-works/pi-coding-agent agent-browser`.

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

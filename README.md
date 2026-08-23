# Ethan's Pi setup

A reproducible, fast [Pi coding agent](https://pi.dev) setup with three entrypoints:

- **`pi`** — full environment without dynamic workflows: Voice STT, native browser
  automation, mid-run and between-runs context compaction, background process monitoring,
  `/btw` side questions, and local MLX model management on macOS.
- **`piwf`** — the same full environment **with** dynamic workflows (the historical `pi`):
  everything `pi` has, plus the `workflow` tool, `/workflows` and `/deep-research`, and the
  workflow-authoring / workflow-patterns skills.
- **`p`** — lean environment with Voice STT, `/btw` side questions, the same two
  compaction extensions, and local MLX model management on macOS, but no browser,
  monitor, workflows, or skills.

All three commands run the same Pi installation through Pi's Bun entrypoint. They share
authentication, model catalogs, sessions, helper binaries, and installed package files.

Every extension is installed from `forks/` as a **security-hardened local fork**, not
from npm. See [Extensions are hardened forks](#extensions-are-hardened-forks) and
[`docs/AUDIT.md`](docs/AUDIT.md).

## Install

This branch is `windows`. Piped installs must fetch it (not `main`) — `install.ps1`
and `lib/install.mjs` are not on `main` yet. Both bootstraps default `PI_SETUP_REF` to
`windows` so the clone matches the script you downloaded.

macOS or Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/ethanewer/pi-setup/windows/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/ethanewer/pi-setup/windows/install.ps1 | iex
```

Git Bash on Windows can run the `install.sh` one-liner instead. Open a new terminal
afterward. The installer is idempotent and preserves unrelated existing Pi packages and
settings.

> Review [`install.sh`](install.sh) or [`install.ps1`](install.ps1) before piping it if
> you do not trust remote scripts. The installer does not copy credentials or API keys.

Both bootstraps run the same [`lib/install.mjs`](lib/install.mjs) once Bun is available.
Pinned versions live in [`lib/versions.json`](lib/versions.json).

## Requirements

- macOS, Linux, or Windows 10+, x86-64 or ARM64 (Windows x64 for `agent-browser`)
- `curl` and `git` (Git for Windows on Windows — Pi needs `bash.exe`)
- `OPENAI_API_KEY` for the configured Pi model and OpenAI transcription
- `ffmpeg` plus microphone permission for Voice STT

The installer installs Bun, Pi, the hardened extension forks, `agent-browser`, and its
Chrome runtime. It warns rather than failing if Chrome or `ffmpeg` setup needs manual
attention.

### Tested platforms

| Platform | How | Covers |
|---|---|---|
| macOS 15 on Apple Silicon | the machine this is developed on | everything, continuously |
| Ubuntu 24.04 x86-64 | [`tests/linux-install.sh`](tests/linux-install.sh) | the piped install as a non-root user, the missing-`unzip` refusal, and `bin/pi-setup-doctor` on a host with no `node` |
| Windows 10 x64 | PowerShell `install.ps1` + `.cmd` shims | installer, `pi`/`p`/`piwf`/`agent-browser` launchers, doctor (via Git Bash), process-tree kill |

Run `tests/linux-install.sh` to reproduce the Linux row; it needs Docker and takes a few
minutes. It sets `PI_SETUP_SKIP_BROWSER_INSTALL=1`, so **Chrome and `agent-browser` are not
exercised on Linux** — that part of the installer is covered on macOS only.

An earlier revision of this file claimed validation on two Ubuntu 22.04 servers including
Chrome and an `agent-browser` smoke test. That was recorded in a documentation-only commit
(`76cc001`) with nothing in the repository reproducing it, so it is left here as history
rather than as a supported claim.

## Installed versions

| Component | Version |
|---|---:|
| `@earendil-works/pi-coding-agent` | `0.84.2` |
| `agent-browser` | `0.34.0` |

Extension forks and the upstream releases they are based on:

| Fork (Pi local package) | Upstream | Upstream version |
|---|---|---:|
| `pi-voice-stt-safe` | `pi-voice-stt` | `0.6.0` |
| `pi-agent-browser-native-safe` | `pi-agent-browser-native` | `0.5.0` |
| `pi-dynamic-workflows-safe` | `@quintinshaw/pi-dynamic-workflows` | `3.7.0` |
| `pi-process-monitor-safe` | `pi-process-monitor` | rewrite, built on `1.3.0`, `2.0.2` reviewed and declined |
| `pi-context-handoff` | — | first-party |
| `pi-btw-side` | — | first-party |
| `pi-setup-maintenance` | — | first-party, skills only |
| `unslop` | — | first-party, skills only |

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

The installer regenerates `~/.pi/agent/npm/package.json` and runs `bun install`, and Pi's
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

### `pi`: full environment without dynamic workflows

`pi` loads the normal package configuration, minus the dynamic-workflows fork. Everything
else ships:

- built-in `read`, `bash`, `edit`, and `write` tools
- Voice STT
- `agent_browser`
- the `update-pi-setup` maintenance skill
- compaction handoff briefs that keep a long run going
- mid-run context folding, so one long run stays inside the context window
- background process monitoring (`monitor`, `/watch`)
- side questions in an ephemeral fork (`/btw`, escape to return)
- project `AGENTS.md` / `CLAUDE.md` context
- visible startup resource listing

The `workflow` tool, `/workflows` and `/deep-research`, and the workflow-authoring skills
are deliberately not loaded — they live behind the `piwf` entrypoint.

### `piwf`: full environment with dynamic workflows

`piwf` is the historical `pi`: the full environment **including** the dynamic-workflows
extension. It runs against its own agent directory `~/.pi/agent-wf` whose settings load
all eight hardened forks. On top of everything `pi` lists, `piwf` adds:

- the `workflow` tool and `workflow_control`
- `/workflows`, `/deep-research`, `/code-review`, and the other built-in workflow commands
- the `workflow-authoring` and `workflow-patterns` skills

`piwf` shares main's session directory, auth, model catalogs, helper binaries, and the
installed package files, exactly like `p`, so its state stays contiguous with the ordinary
`pi`.

### `p`: lean environment

`p` invokes the same Pi and package installation with:

```text
--no-extensions --no-skills
```

It explicitly reloads only Voice STT, `/btw`, both compaction extensions, the conditional
`mlx` extension, and a tiny local extension that removes Pi's documentation block from the
system prompt. The exact allowlist keeps the heavier browser, monitor, and workflow
extensions out. It also:

- uses quiet startup
- skips the Pi version check
- shares the main session directory
- shares auth, model catalogs, and helper binaries

`p` uses a small settings overlay at `~/.pi/agent-p/settings.json`; it is a configuration
profile, not another Pi installation. The `pi` wrapper explicitly rejects an inherited
`p` or `piwf` profile environment, so a tmux server started from either cannot
accidentally turn later `pi` sessions into a different configuration.

## Default model scope

All three entrypoints (`pi`, `piwf`, and `p`) restrict Ctrl+P model cycling (the
`/scoped-models` list) to exactly these models via `enabledModels` in each profile's
settings (`~/.pi/agent`, `~/.pi/agent-wf`, and `~/.pi/agent-p`):

```text
openrouter/deepseek/deepseek-v4-flash-0731
openrouter/deepseek/deepseek-v4-pro-0813
openrouter/z-ai/glm-5.2
openrouter/z-ai/glm-5.3
openrouter/moonshotai/kimi-k3
openrouter/qwen/qwen3.8-max
openai/gpt-5.6-sol
openai/gpt-5.6-terra
openai/gpt-5.6-luna
```

The patterns are canonical `provider/id`, so each matches exactly one model. Two
consequences of how Pi applies the list are worth knowing:

- It is a managed default: `install.sh` rewrites `enabledModels` on every install, so a
  scope changed through `/scoped-models` reverts at the next reinstall.
- When a profile's saved default model is **not** in the scope, Pi starts new sessions on
  the first scoped model (`openrouter/deepseek/deepseek-v4-flash-0731`) instead of the saved default. All
  three profiles' current defaults are inside the scope, so this only bites if the
  default is later changed to something outside it.

## Local MLX models (`/mlx`, macOS only)

The `mlx` extension is installed for both `p` and `pi`, but registers itself only on macOS.
It owns the server it starts and never takes over an occupied port.

```text
/mlx download optimized-ornith
/mlx list
/mlx load mlx-works/Ornith-1.5-35B-A3B-oQ4e-mtp
/mlx stop
```

The download command fetches the calibrated Ornith-35B oQ4e trunk and builds the locally
optimized Qwen3.6-donor overlay. Only the actively served model appears in Pi's `/model`
list; downloaded models remain visible through `/mlx list`. MTP is off by default after an
agentic A/B regression and can be enabled for diagnostics with `MLX_ORNITH_MTP=1`.

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

Use **Option+P** on macOS or **Alt+P** on Linux and Windows to start recording. The text cursor
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

> Do not run `pi update` or `bun add --global` for Pi or the extensions. The installer
> pins both versions and rewrites the wrappers; anything installed around it is reverted
> by the next run and reported as drift by `bin/pi-setup-doctor`.

### Check the installed setup

```bash
bin/pi-setup-doctor
```

Verifies that every fork in `forks/` matches the copy installed under
`~/.pi/agent/local/`, that Pi's settings load the forks and not the unpatched npm
packages, that `stt.json` is owner-only, that `trust.json` has no home-wide entry, and
that the installed Pi and `agent-browser` match the versions `lib/versions.json` pins, and that
`pi-dynamic-workflows-safe`'s `dist/` still mirrors its `src/` — the package exports reach
both, so a stale `dist` would export code nobody audited. It also checks
`compaction.reserveTokens` against [`config/compaction.json`](config/compaction.json),
which is the same file the installer applies: too small and a long agentic turn overshoots
the context window, too large and the summarization call stalls. See
[`docs/LONG_RUNS.md`](docs/LONG_RUNS.md). Also reports when npm has published a newer
release than this repository pins, for Pi, `agent-browser`, or a fork's upstream. Exits
non-zero on problems, so it can gate CI.

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
./install.sh                                         # reinstall (or .\install.ps1 on Windows)
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

Update `pi` in `lib/versions.json`, test on macOS, Linux, and Windows, and rerun the installer.
The wrappers locate the installed Pi package dynamically, so they need no changes.
`pi-context-handoff` uses only Pi's public API (`compact`, the
`session_before_compact` hook, and the `context` hook for its merged-in mid-run fold), so a
Pi upgrade should not disturb it. If Pi ever changes those hooks' contracts the extension
degrades to native compaction / an unfolded request rather than failing. One shape it checks
at runtime: it builds Pi's `compactionSummary` message by hand, because
`createCompactionSummaryMessage` is not exported from the package root, and verifies once
per session that `convertToLlm` still renders it — falling back to a plain user message if a
Pi release ever stops.

## Evals

`evals/` holds behavioral evals for this setup's extensions. The first one is
**monitor-bench**: scripted tasks with long, seeded, unknown-duration commands (test
suites, crashing pipelines, slow-boot servers, detached batch jobs) plus
a fast control task. The prompts never mention background watching; the eval measures
whether a model spontaneously reaches for the monitor extension, whether it trusts the
pings enough to stop blocking, and whether it still completes the goals.

```bash
cd evals
SEED=42 MODEL="openai/gpt-5.6-sol" ./run.sh   # all tasks in parallel
python3 score/score.py results/latest
```

See [`evals/README.md`](evals/README.md) for task design, metrics, and reference results
(four models x three seeds: adoption 10–12/12 long-job tasks, genuine ping-waiting
8–11/12; the eval also drove a simplification of the monitor extension's model surface
from 4 tools/10 params/3 guidelines to 3/6/1, which improved trust for every model).

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
~/.local/bin/pi                              Full entrypoint (no dynamic workflows)
~/.local/bin/piwf                            Full entrypoint with dynamic workflows
~/.local/bin/p                               Lean entrypoint
~/.local/bin/agent-browser                   Bun-backed agent-browser entrypoint
~/.local/bin/pi-agent-browser-config         Browser config CLI
~/.local/bin/pi-agent-browser-doctor         Browser diagnostics CLI
~/.local/bin/*.cmd                           Windows cmd.exe/PowerShell shims (Windows only)
~/.local/lib/pi-coding-agent/pi.exe          Compiled Pi binary (Windows only, optional)
~/.pi/agent/settings.json                    Main Pi settings (no workflow package)
~/.pi/agent/stt.json                         Voice STT configuration (mode 600 on Unix)
~/.pi/agent/keybindings.json                 Keys remapped for tmux, Kitty, and Windows Terminal
~/.pi/agent/local/                           Hardened extension forks
~/.pi/agent/extensions/mlx/                  Conditional local MLX extension
~/.pi/agent/npm/                             Shared extension packages (no longer used
                                             by this setup; pruned on install)
~/.pi/agent/setup-src/                       Clone of this repository, when the
                                             installer is piped from curl or irm
~/.pi/agent/p/remove-pi-documentation.js     Lean prompt filter
~/.pi/agent-p/settings.json                  Quiet lean settings overlay
~/.pi/agent-p/keybindings.json               The same remapped keys for the lean profile
~/.pi/agent-p/auth.json                      Symlink (or copy on Windows without Developer Mode) to main auth
~/.pi/agent-p/models-store.json              Symlink/copy to main model catalog
~/.pi/agent-p/bin                            Symlink/junction to main helper binaries
~/.pi/agent-wf/settings.json                 Full settings overlay incl. the workflow fork
~/.pi/agent-wf/keybindings.json              The same remapped keys for the piwf profile
~/.pi/agent-wf/auth.json                     Symlink/copy to main auth
~/.pi/agent-wf/models-store.json             Symlink/copy to main model catalog
~/.pi/agent-wf/bin                           Symlink/junction to main helper binaries
~/.pi/agent-wf/local                         Symlink/junction to main hardened fork install
```

The installer adds `~/.local/bin` and `~/.bun/bin` to `.zshrc` and `.bashrc`, and on
Windows to the user PATH plus the PowerShell profile.

There is exactly one entrypoint per command. Pi is installed once, globally, by Bun;
`bun add --global` also links its own `pi` and `agent-browser` shims into `~/.bun/bin`,
and the installer removes them. Those shims point at the same installation but bypass the
wrappers above — notably `pi`'s guard against inheriting the lean `p` or full `piwf`
profile environment from a tmux server. If you previously installed Pi another way (npm
global, Homebrew), remove it:
`npm uninstall -g @earendil-works/pi-coding-agent agent-browser`.

## Session archives

Session archives are intentionally excluded. To archive sessions older than 30 days,
preserve paths inside the archive and verify it before deleting originals.
Authentication files, model credentials, session transcripts, SSH material, and API keys
must never be committed here.

### Exporting traces to a dataset

`bin/convert-pi-traces` turns local pi sessions into the row format of the private
[`eewer/glm-5.2-multi-harness-agent`](https://huggingface.co/datasets/eewer/glm-5.2-multi-harness-agent)
dataset and uploads the compressed result to
[`eewer/pi-trace-cache`](https://huggingface.co/datasets/eewer/pi-trace-cache) when
`HF_TOKEN` has write access. It enforces three invariants by default:

- **OpenAI and Anthropic models are dropped** (by provider and model id).
- **Fake test/mock models are dropped** — pi's `faux` provider and the Qwen3 0.6B
  model are test fixtures, not real sessions.
- **Every API key is replaced with a deterministic, format-valid fake** — the same
  real key always maps to the same fake, so traces stay valid while no real secret
  leaves the machine.

Benchmark rollouts (TerminalBench, tau-bench, …) are also dropped; a dev session
that merely *mentions* a benchmark is kept. Run `bin/convert-pi-traces --dry-run`
to preview, and inspect `~/pi-trace-cache-tool/out/*.jsonl` before sharing. It is a
standalone Python tool (`pip install zstandard huggingface_hub`), not part of the
install.

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

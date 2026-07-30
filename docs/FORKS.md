# What each fork changes

The forks in `forks/` fix the findings in [`AUDIT.md`](AUDIT.md). This file records what
changed behaviourally, what now needs an explicit opt-in, and the **residual risk** that
remains. Nothing here is a sandbox — these are hardened extensions running with your full
permissions.

Fixing took four rounds. Each round was reviewed by an independent adversarial pass
instructed to *refute* the fixes and hunt for feature regressions rather than confirm them.
That pass repeatedly found guards that looked correct and protected nothing, so the rounds
below are the record of a converging process, not four attempts at the same thing.

Every patch in `patches/` reproduces its fork byte-for-byte from pristine upstream:

```bash
bin/pi-setup-vendor --verify <fork>
```

## Principles the fixes follow

1. **No feature was removed.** Where a capability was genuinely dangerous, it was gated,
   confined, or put behind a confirmation — never deleted. Everything still reachable is
   listed under "Now needs an opt-in" below.
2. **Fail closed on an unknown host.** Where an extension asked Pi a question it might not
   be able to answer (`ctx.isProjectTrusted`), the answer defaults to *untrusted*. Upstream
   defaulted to trusted.
3. **Project-local files are untrusted input.** Every path where a repository could supply
   configuration, a prompt, a script, or a run record is now trust-gated.
4. **Confinement means `realpath`.** String comparison of `resolve()`d paths was the single
   most common broken guard; a symlink inside the workspace walks straight through it.
5. **A guard is never weakened to restore a capability.** Where restoring convenience would
   have reopened a hole, the hole stayed closed and the error message names the opt-in.

## pi-dynamic-workflows-safe

Based on `@quintinshaw/pi-dynamic-workflows@3.4.1`. `src/**/*.ts` is the tree Pi loads;
`dist/` is the compiled mirror shipped through the package `exports` field.

**Closed.** The zero-click RCE chain is broken at every link: persisted run records are
schema-validated instead of trusted, each record carries the provenance of the install that
wrote it, and `coldStartRearm` will only auto-resume a run this install created in its own
global store. A repo-local run under `.pi/workflows/runs` can still be listed, inspected and
resumed — but only on an explicit action that names the file, never automatically. The `vm`
realm no longer hands script code a host function: the bridge is removed from the realm's
global after an in-realm bootstrap closes over it, values crossing back are deep-cloned, and
host errors are surfaced as realm-native errors, so `log.constructor` is the realm's
`Function` rather than the host's. `runInContext` has a timeout, so a runaway script can no
longer wedge the whole Pi event loop. `runId` is charset-validated everywhere it reaches the
filesystem. Repo-local saved workflows can no longer silently shadow a built-in command.
Run state is written `0600` inside `0700` directories. `web_fetch` refuses loopback,
link-local and private-range targets. Worktree isolation ids are collision-free and a failed
worktree fails loudly instead of silently running in the shared tree.

**`src`/`dist` divergence eliminated.** Three rounds of hand-mirroring had left seven files
in `dist/` byte-identical to vulnerable upstream, so the audited code and the exported code
were not the same code. The fork now ships a `tsconfig.json` that compiles *pristine* `src`
into byte-identical *pristine* `dist` (94/94 files) — proving it reconstructs the original
build — and `dist` is a clean-room `tsc` build of the fork's `src`. Rebuild with
`npm run build`.

**Default changes.** A run defaults to 100 agents (was 1000).
`DEFAULT_AGENT_TIMEOUT_MS` is 60 minutes (was unbounded), sized so a legitimately long
subagent is not silently degraded to `null`. `DEFAULT_AGENT_RETRIES` is 2 with exponential
backoff (was 0), because a transient provider fault was the most common way a long run
lost work — see [`LONG_RUNS.md`](LONG_RUNS.md). The 1000 ceiling is still reachable via
`maxAgents`/`defaultMaxAgents`, and `agentTimeoutMs: null` restores unbounded agents. New
settings: `trustProjectLocalWorkflows`, `webFetchAllowedHosts`,
`webFetchAllowPrivateNetwork`, `worktreeIsolationFallback`, `defaultMaxAgents`.

**Residual risk.** A cloned repo can no longer get code executed with zero clicks, but it
can still put a confirmation dialog in front of you — for a repo-local run record, a
repo-local saved workflow, or one shadowing `/code-review`. The prompt names the exact file;
clicking through it runs attacker code. Social engineering is the residual. Separately,
`workflow` remains a high-capability tool by design: the realm no longer yields host
JavaScript execution, but a workflow script still directs subagents that hold
read/bash/edit/write in the working directory without a per-action approval prompt. Closing
that would mean removing the feature. On a shared or network-synced run store, a foreign-host
lock is reclaimable after a staleness window rather than immediately.

## pi-agent-browser-native-safe

Based on `pi-agent-browser-native@0.2.72`, which rebaselines the wrapper to
`agent-browser 0.33.0` (so `install.sh` pins that). Only `dist/` is shipped, so the fixes
are in the compiled tree.

Re-vendored onto 0.2.72 on 2026-07-30. One conflict, in `package.json` (the version bump
against this fork's `private: true`), resolved by hand; every other hunk applied cleanly.
Upstream's code delta was additive — `--content` and `--tags` became value-taking flags —
and was re-reviewed against the hardening: the write-path guards, the project-scope
credential rule, the privileged-flag gate and the upstream-config pin were all re-verified
functionally after the merge, including that the two new flags are not mistaken for write
paths.

**Closed.** `isProjectSafeCredentialValueForProvider` — a stub that returned `true` for any
non-empty string — is implemented, so a project-scope credential can no longer be a
`!command` or a plaintext literal; `!command` values run through `execFile` with an argv
array instead of a shell. Project config is only honoured when Pi reports the project
trusted, and a host that cannot answer now fails *closed*.

Critically, gating the privileged flags was not enough on its own: upstream `agent-browser`
auto-discovers `./agent-browser.json` from its working directory and, per its own `--help`,
that project file *overrides* user defaults — so a repo needed no flag at all to supply
`executablePath`, `initScripts`, `proxy` and `allowFileAccess`. The wrapper now pins the
child's configuration so a repo-local file cannot apply silently.

Write paths are confined by `realpath` of the deepest existing ancestor (not by string
comparison) and refuse `.git`, across every entry point — `outputPath`, download, pdf,
screenshot, state save, the `mkdir -p` paths, and batch steps in *both* JSON-stdin and
argument mode, the latter tokenized the way upstream tokenizes it. Electron launches require
real framework evidence and a `CFBundleExecutable` with no path separators, and `appArgs` is
an allowlist that rejects `--*-launcher`, `--*-cmd-prefix`, `--no-sandbox`,
`--load-extension` and `--disable-web-security`. `--allowed-domains` treats a non-`http(s)`
URL as a violation rather than as no-violation. POSIX children run in their own process group
so timeout and abort actually reap descendants. The CLI path is pinned rather than resolved
through `PATH`.

**Residual risk.** `--download-path` and `--screenshot-dir` are `.git`-guarded but
deliberately *not* workspace-confined, so a model can still place artifacts in a writable
directory outside the workspace — the price of keeping upstream download directories usable.
Writes inside the workspace are still writes: content that lands in a tracked file is a
supply-chain risk if committed unreviewed. `scripts/doctor.mjs` still runs
`agent-browser --version` unpinned in the operator's directory; verified empirically against
a hostile project config that `--version` reaches no privileged key and launches no browser.

## pi-continue-safe — retired

Removed. It replaced Pi's native compaction with an abort-summarize-prove-resume pipeline
whose every link could stop a long run, and it was strictly less resilient than the Pi
behaviour it displaced. Replaced by
[`pi-context-handoff`](../forks/pi-context-handoff/README.md); the reasoning and the
evidence are in [`LONG_RUNS.md`](LONG_RUNS.md). Its 21 verified security fixes are moot
now that the code is not installed, and git history retains the fork.

## pi-context-handoff

First-party, not a fork. Steers Pi's own compaction toward a handoff brief and does nothing
else: hook `session_before_compact`, call Pi's `compact()` with focus instructions plus a
retry policy, return the result.

It **cannot stop a run** — no `ctx.abort()`, no injected messages, no `{ cancel: true }`.
Every failure path returns `undefined`, which is exactly the behaviour of not having it
installed, so the worst case is a less useful summary. It uses only Pi's public API, which
also removes the deep private-module imports that made the previous extension fragile
across Pi releases.

## pi-btw-side

First-party, not a fork. Implements Codex's `/side` — aliased `/btw` there too — as
`/btw <question>`: an ephemeral fork of the current conversation that answers a side
question without the question or the answer entering the main thread's context. The
boundary prompt and developer instructions are Codex's, from
`codex-rs/tui/src/app/side.rs`.

`/btw` switches the screen to a clean side conversation and escape returns, the way Codex
switches to a forked thread and returns on Ctrl+C. The inherited history is context for
the model but is not displayed — Codex's `install_side_thread_snapshot` does the same, and
for the same reason: a side conversation should visually start at the boundary. The view
is rendered with Pi's own message components, so it looks like the real chat.

One deliberate departure: the side thread gets **read-only tools** by default (`read`,
`grep`, `find`, `ls`) instead of inheriting the parent's. Codex relies on prompt
instructions to keep a side thread non-mutating, but a Pi sub-session runs without an
approval prompt in front of it, so the restriction is structural here. `"toolset": "full"`
restores Codex's behaviour.

It **cannot stop a run**. The fork is a separate `AgentSession` with an in-memory session
manager and the view is an overlay, so the host session is neither aborted, paused, nor
added to. The main thread keeps streaming behind the view — verified — and the header
reports whether it is still working, since its transcript is hidden while the view is up.
The mid-turn history snapshot is trimmed back to the last resolved tool call so a
half-finished turn cannot produce an invalid request.

## pi-voice-stt-safe

Based on `pi-voice-stt@0.4.0`.

**Closed.** A named vendor alias is pinned to that vendor's host, and — the gap that survived
the first two rounds — a defaulted `OPENAI_API_KEY` can never follow a non-OpenAI host. A
custom endpoint is still fully supported through `openai-compatible` or `local`, but it must
name the secret it receives explicitly (`apiKeyEnv`, `apiKeyFile`, `keychainService`, or an
explicit `""` for deliberately keyless). Gladia's server-controlled `result_url` is validated
and must stay on the configured registrable domain. `capture.ffmpegPath` is resolved to a
`realpath` and must be an executable regular file, reported at point of use so `/stt doctor`
still works when `ffmpeg` is missing. The optional macOS bridge daemon refuses to start
without a token instead of authenticating everyone, compares bearer tokens in constant time,
and refuses a non-loopback bind without `PI_STT_BRIDGE_ALLOW_REMOTE`.

The hot-mic race is fixed: `disposed` is re-checked after `recorder.start()` resolves and a
partially started recorder is released, so a shutdown mid-start no longer orphans a live
`ffmpeg` holding the microphone. `maxSeconds` is enforced by `ffmpeg -t` rather than a JS
timer that could silently never fire. A cancel during startup no longer latches and silently
discards the *next* transcript. Replacements no longer treat `$&` in a value as a
substitution pattern, and accented keys such as `café` now match — which the shipped French
locale depended on.

**Residual risk.** Anyone who can write `~/.pi/agent/stt.json` can still send your
microphone audio to an arbitrary HTTPS host by naming a credential explicitly, or run any
already-executable binary via `capture.ffmpegPath`. Both are the documented feature set; the
fix removed the *silent* variants, where a defaulted key followed a host you never named.
`install.sh` keeps that file mode `600` and `bin/pi-setup-doctor` checks it.

## pi-process-monitor-safe

A hand-written rewrite of `pi-process-monitor@1.2.0`, imported into this repository with its
original commit history. It adds a watcher cap, kill-all, aggregated heartbeats, and safe
session shutdown with no persistence or restore. Not re-vendorable with
`bin/pi-setup-vendor`; maintained directly.

## pi-setup-maintenance

First-party, skills only: no extensions, no tools, nothing loaded into a running session
beyond one skill description. It carries `update-pi-setup`, the procedure for updating Pi,
`agent-browser`, and each fork, plus what to re-review after an upstream merge and how to
roll back.

It exists because the failure mode is predictable: an agent told to "update pi" reaches
for `pi update`, which bypasses the version pin in `install.sh`, is silently reverted by
the next install, and shows up later as drift. The skill puts the pinned path where an
agent will find it. `bin/pi-setup-doctor` now reports that drift directly, comparing the
installed Pi and `agent-browser` against the versions `install.sh` pins.

## Startup labels

Pi labels an extension by the directory holding its index file, falling back to the bare
filename when the entry is not an `index.*` (`modes/interactive/interactive-mode.js:891`).
Upstream `pi-voice-stt` points at `src/index.ts` and upstream dynamic-workflows at
`extensions/workflow.ts`, so the startup listing read `src` and `workflow.ts`. Both forks
now use the `extensions/<name>/index.ts` convention the other three already followed, so
the listing identifies every extension by name:

```text
[Skills]
  monitor, update-pi-setup, workflow-authoring, workflow-patterns

[Extensions]
  agent-browser, btw, context-handoff, monitor, voice-stt, workflow
```

For voice-stt that entry is a one-line re-export; `src/` is still the implementation. For
dynamic-workflows the entry file moved into its own directory and its two relative imports
were repointed. Nothing else changed.

A stray upstream package is still distinguishable at a glance: Pi prefixes `npm:` and
`git:` sources with the package spec (`pi-voice-stt@0.4.0:src`) and leaves `local/`
sources bare, so anything showing a version prefix is not one of these forks.

## Now needs an opt-in

Every capability below still works — it just requires a deliberate setting, because it was
reachable by repo-controlled or model-chosen input before.

| Opt-in | Restores |
|---|---|
| `PI_AGENT_BROWSER_ALLOW_PRIVILEGED_FLAGS` | `--executable-path`, `--args`, `--init-script`, `--extension`, `--proxy`, `--config`, `--allow-file-access` in raw `args` |
| `PI_AGENT_BROWSER_TRUST_PROJECT_CONFIG` | Project-scope browser config, including upstream's `./agent-browser.json` |
| `PI_AGENT_BROWSER_ALLOW_UNCONFINED_WRITES` | Writes outside the workspace |
| `PI_AGENT_BROWSER_ALLOWED_WRITE_ROOTS` | Additional approved write roots |
| `PI_AGENT_BROWSER_ALLOW_PROJECT_CREDENTIAL_COMMANDS` | `!command` credential sources from project scope |
| `PI_AGENT_BROWSER_CLI_PATH` / `PI_AGENT_BROWSER_ALLOW_WORKSPACE_CLI` | A pinned or workspace-local `agent-browser` binary |
| `PI_AGENT_BROWSER_ELECTRON_EXTRA_APP_ARGS` | Electron switches outside the allowlist |
| `PI_AGENT_BROWSER_ELECTRON_APP_URL_SCHEMES` | Extra schemes exempt from `--allowed-domains` |
| `PI_AGENT_BROWSER_FORWARD_ALL_ENV` | Forwarding loader vars (`NODE_OPTIONS`, `LD_PRELOAD`, …) to the child |
| `PI_AGENT_BROWSER_ALLOW_DIRECT_BASH` | Calling `agent-browser` directly from `bash` (upstream gate, not added here) |
| `PI_AGENT_BROWSER_SKIP_ORPHAN_ELECTRON_ADOPTION` | Skipping adoption/cleanup of Electron processes orphaned by a previous run |
| `PI_STT_ALLOWED_ENDPOINT_HOSTS` | Additional hosts accepted for a named vendor alias |
| `PI_STT_BRIDGE_ALLOW_REMOTE` | Binding the bridge daemon beyond loopback |
| `trustProjectLocalWorkflows` | Repo-local saved workflows and run records |
| `webFetchAllowedHosts` / `webFetchAllowPrivateNetwork` | `web_fetch` to loopback or private ranges |
| `worktreeIsolationFallback` | Continuing when `git worktree add` fails |
| `defaultMaxAgents` / `maxAgents` | Raising a run above the 100-agent default, up to the 1000 ceiling |
| `defaultAgentTimeoutMs` / `agentTimeoutMs: null` | Removing the 60-minute per-agent timeout entirely |
| `toolset: "full"` (`pi-btw-side.json`) | Giving a `/btw` side thread `bash`, `edit`, and `write`, which is Codex's own side-thread toolset |

One gate is a configuration shape rather than a flag: in `pi-voice-stt-safe` a named vendor
alias is pinned to that vendor's host, so sending audio to a custom endpoint requires
`"type": "openai-compatible"` (or `"local"`) **and** an explicitly named secret
(`apiKeyEnv`, `apiKeyFile`, `keychainService`, or an explicit `""` for deliberately
keyless). A defaulted `OPENAI_API_KEY` can never follow a host you did not name.

## Verification

Findings were only treated as closed with traced evidence, and many were settled by
executing the code rather than reading it: a differential harness proved the microphone
orphan (pristine leaves a live recorder, the fork disposes it), measured `ffmpeg` output
proved the duration cap (2.000 s of audio after 5 s of wall clock), a live exploit proved the
browser config discovery, a 400k-case fuzz against an independent oracle checked the loopback
predicate, and a byte-comparison of `tsc(pristine src)` against pristine `dist` proved the
reconstructed build. The `.git` write guard was re-tested here against a real fixture
repository across plain, quoted, case-folded, nested and symlinked spellings.

Known-good upstream behaviour was explicitly preserved rather than rewritten: the browser
package's redaction, ANSI stripping and ownership-verified temp handling; pi-continue's tag
escaping, schema validation and terminal-escape stripping; voice-stt's `mkdtemp` audio
staging and its correct shell-free Keychain call.

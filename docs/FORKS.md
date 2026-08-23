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

Based on `@quintinshaw/pi-dynamic-workflows@3.6.0`. `src/**/*.ts` is the tree Pi loads;
`dist/` is the compiled mirror shipped through the package `exports` field.

This fork is loaded only by the `piwf` entrypoint (`~/.pi/agent-wf/settings.json`), the
historical `pi`. The default `pi` profile deliberately excludes it, so `pi` has no
`workflow` tool, `/workflows` commands, or workflow skills. Re-adding it to `pi`
(not just `piwf`) makes `bin/pi-setup-doctor` report it so the split stays intentional.

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

Re-vendored onto 3.5.0 on 2026-07-30. Upstream's delta was small (7 files, 142 lines) but
landed on the files this fork patches hardest, and it is worth having: an unresolvable
`model` or `tier` used to fall back to the session default silently, and now throws
`MODEL_NOT_FOUND` — a wrong-model run that looked successful is exactly the failure this
setup cares about. One hunk rejected, in the capability contract, because upstream rewrote
the line above this fork's worktree-isolation constraint; resolved by hand in the contract,
its `dist` mirror and both authoring-skill references. The hardening was re-verified
against the merged tree: cold-start rearm provenance, the vm timeout, the web-fetch host
gate, project-local workflow trust, the worktree fallback gate and the agent ceiling are
all still in place.

Re-vendored onto 3.5.1 on 2026-08-06. Six source hunks rejected, because upstream moved to
live `getManager`/`getCwd`/`getStorage` getters throughout and more than doubled the
extension entrypoint (151 to 338 lines) for cross-project session handling. Each was
resolved by hand onto the new structure: the `installId`/`foreignSource` provenance stamps,
the project-supplied-workflow save gate, the repo-local gate on shadowed built-in commands,
the `fenceUntrusted` export, and — on the rewritten entrypoint — the web-fetch policy, the
agent ceiling, the worktree-isolation fallback, the foreign-run confirmation and the
one-shot active-tool registration.

Two things changed rather than transferred. Upstream now pauses stranded runs itself on
every non-handoff shutdown, which is what this fork added at 3.5.0, so that hunk is
retired rather than reapplied. And upstream narrowed `registerSavedWorkflow`'s `wf`
parameter to the four execution fields, dropping `path`, `repoLocal` and `scriptOrigin` —
exactly the provenance the trust gate reads. Reapplying the gate verbatim would have
compiled only because the old wider type was still in place; on 3.5.1 it is a type error,
caught by typecheck. The parameter and the live-loader return type were widened back, and
the gate now reads the *live* workflow rather than the registration-time snapshot, so a
name that resolves to a repo-local script after an in-process project switch is still
gated.

Re-vendored onto 3.6.0 on 2026-08-18. Upstream added strict model-spec parsing, bounded
code-review diff capture with generated-artifact auto-scoping, increase-only `maxAgents`
on resume, and durable background-result delivery. The merge retained this fork's
option-shaped git argument rejection and revision terminator, install/run provenance,
untrusted-result fencing, agent defaults and ceiling, and rebuilt `dist/` from the merged
`src/` tree.

Re-vendored onto 3.7.0 on 2026-08-22. Upstream added named-thread subagent conversations
(re-enterable within one workflow invocation), with live-execution resume barriers so a
threaded call is never journaled or replayed, a same-thread sequential-execution guard, and
a refusal to combine a thread with worktree isolation. Two hunks rejected — both the fork's
own edits, not upstream's: `README.md` (the trust/untrusted-input block lost its trailing
context line to a rewording of the in-memory session note) and `package.json` (`"private":
true` lost its context to the version bump) — resolved by hand onto the 3.7.0 lines. The
hardening was re-verified against the merged tree: cold-start rearm provenance, the vm-realm
timeout, the web-fetch private/loopback host gate (fail-closed, `webFetchAllowPrivateNetwork`
defaults false), project-local workflow trust, the worktree-isolation fallback, the foreign-run
confirmation, the agent ceiling and `DEFAULT_AGENT_TIMEOUT_MS`/`DEFAULT_AGENT_RETRIES`, and
`runId` charset validation are all still in place. `dist/` was rebuilt as a clean-room `tsc`
build of the merged `src/` (47/47 modules mirrored; the fork's `DEFAULT_AGENT_RETRIES`/
`DEFAULT_AGENT_TIMEOUT_MS`/`defaultAgentRetries` constants present in both) and is byte-identical
to the patched tree; `bin/pi-setup-vendor --verify` reproduces the fork exactly.

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

Based on `pi-agent-browser-native@0.3.0`, which targets `agent-browser 0.33.2` (which
`install.sh` pins). Only `dist/` is shipped, so the fixes are in the compiled tree.

**Re-vendored 0.2.72 -> 0.2.77 on 2026-08-04, and this one was a real merge.** Five upstream
releases landed a new managed-session subsystem (nine new modules, crash-safe restore keys,
process identity, socket-directory ancestry validation) and touched 22 of the 37 files this
fork patches. `patch` rejected 14 files, so the merge was redone as a git three-way merge —
upstream 0.2.72 as base, the fork and 0.2.77 as branches — which reduced it to 21 conflict
hunks across 15 files. `dist/extensions/agent-browser/lib/process.js` was rebuilt by taking
upstream's rewritten file and re-porting the eight hardening concerns onto it, because both
sides had restructured the same functions.

Two resolutions are judgement calls worth knowing:

- **Config pinning is now layered.** Upstream 0.2.74 added its own pin: browser-backed calls
  reject discovered config unread and get a process-private empty config, and its
  `trustedPinnedEmptyConfig` policy flag is derived from that variable. This fork's pin —
  which copies the *user's* config so user defaults keep applying — now runs only where
  upstream pinned nothing, notably plain-text inspection commands. Two pins can never
  overwrite each other, and upstream's policy flag stays truthful.
- **Windows CLI resolution.** Upstream replaced the launcher with a `Get-Command` probe plus
  a missing-command marker, which is PATH resolution and undoes the pin. The fork keeps the
  pinned path when one resolves and falls back to upstream's probe only when nothing was
  pinned, so `isWindowsAgentBrowserCommandMissing` still works.

Every hardening item was re-verified against the merged tree rather than assumed. Statically:
the credential validator is still implemented (not the upstream stub), there is no `shell:
true` anywhere and `!command` still goes through `execFile` with an argv array, the Electron
code-execution denylist and `-launcher`/`-cmd-prefix` patterns are intact, and write-path
confinement still reaches `prepare`, `direct-anchor-download` and `output-file`.
Functionally, against the merged build: a page opens and returns its title; a screenshot
inside the workspace is written; a write to `$HOME` and a write into `.git` are both refused
with the fork's own messages and neither file exists on disk; a workspace-local
`agent-browser` shim is never executed; and a hostile repo-local `agent-browser.json`
naming an `executablePath` is refused in 7s without the named binary ever running.

One upstream behaviour change to expect: 0.2.77 verifies artifacts, so a `close` that follows
a refused screenshot is itself policy-blocked until the artifact is resolved. That is
upstream working as designed, not a merge defect — it surfaced as a confusing
"artifact guard blocked close" during verification.

Re-vendored onto 0.3.0 on 2026-08-18. This release raises the Pi support floor to 0.84.0
and reorganizes input/result modules while retaining the `agent-browser 0.33.2` capability
baseline. A three-way merge kept config trust fail-closed, credential commands shell-free,
write-path and Electron confinement, launch-flag policy, and managed-session protections.
The external CLI pin therefore remains 0.33.2; 0.34.0 is a separate re-baseline rather
than part of this extension update.

Re-vendored onto 0.5.0 on 2026-08-22, and rebaselined the external `agent-browser` CLI pin
0.33.2 -> 0.34.0 — the coupled job the 0.3.0 entry above deferred. Seven upstream releases
(0.4.0-0.5.0) landed a top-level one-shot `script` code mode with a permissioned child and a
durable pre-spawn lease, Android/Termux support, the exact-runtime version gate
(`upstream-version.js`), managed-restore keys scoped to both checkout generation and Pi
transcript, profiled/`--args`/`--user-agent` session preservation, `--pin-tab`/`--no-pin-tab`
sticky tab binding with CDP `targetId` refs and `tab_gone` recovery, and the 0.34.0 capability
baseline (`scripts/agent-browser-target.mjs` pins `TARGET_AGENT_BROWSER_VERSION = "0.34.0"`,
`inventorySections` include `--pin-tab`/`--no-pin-tab`/`tab_gone`/`data.targetId`, and the
`upstreamHead` is `548b159b30eef119ccf6846c8bc807d0eaa3f6f8`).

13 patch hunks rejected across 10 files; every one was the fork's own hardening edit that
lost its context line to upstream's restructuring, not upstream's work. Resolved by hand:
the CLI-path-pinning spawn call (`{cwd, env}` + `spawnCommand.error` + `detached` process group)
and the `child-process-policy`/`upstream-config-policy` imports in `process.js`; the
`getPrivilegedFlagValidationError` validation-chain entry and the `launch-flag-policy`/
`argv-grammar` (`getFlagName`, `isBooleanFlagEnabled`) imports in `runtime.js`; the
allowed-domains `allowLocalAppUrls`/`localAppFileRoots` call in `process-output.js` (upstream
already adopted the `getAllowedDomainsViolation` params and `getLocalAppFileRootsForLaunch`);
the `adoptOrphanedElectronLaunches`/`planUpstreamConfigPin`/`getUpstreamProjectConfigIgnoredNotice`
imports and the `readPackageJson` helper in `index.js`; the `getFlagName` import in
`artifact-paths.js`; the Electron launch schema hardening descriptions in `params.js`; the
"two layers" config-pin + privileged-`--config`-flag-gating + env-var-stripping (`NODE_OPTIONS`/
`LD_PRELOAD`/`DYLD_INSERT_LIBRARIES`/`ELECTRON_RUN_AS_NODE` + workspace-local `PATH`) paragraphs
in `COMMAND_REFERENCE.md`; the 0.34.0 SUPPORT_MATRIX rebaseline note; and the `"private": true`
and CLI-path-pinning paragraphs in `package.json`/`README.md`. Upstream already adopted the
config pin (0.4.1), the exact-runtime gate (0.4.1), the CLI-path resolution (0.5.0), and the
privileged-flag policy (0.5.0); the fork's patch now layers the sessionless `AGENT_BROWSER_CONFIG`
pin, the env-var/PATH stripping, and the Electron schema descriptions on top.

The 0.34.0 re-baseline was checked the same way as every prior one: all 56 help surfaces the
baseline samples were diffed between the two published binaries. 53 are byte-identical and
the other 3 (root help, core skill full, tab help) are purely additive — nothing was removed
anywhere. Root help gains `--pin-tab`/`--no-pin-tab` (`AGENT_BROWSER_PIN_TAB`), `tab --help` gains
CDP `targetId` as a tab ref and `tab_gone` recovery, and the core skill gains a tab-pinning
section. The command set is unchanged — `tab`, `tab list`, `tab close`, `tab new` already
existed and are already in `inventorySections` — so the artifact-path guards that key off
command prefixes are unaffected. `--pin-tab`/`--no-pin-tab` are sticky optional global booleans
(not launch-scoped), already in `GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES`, so no new flag
reaches the argv tokenizer unhandled.

Hardening re-verified against the merged tree: config trust fails closed (project config only
when Pi reports the project trusted; the `AGENT_BROWSER_CONFIG` pin for sessionless commands
layers on upstream's empty-config pin for browser-backed calls), `!command` values through
`execFile` with an argv array, write-path confinement by `realpath` refusing `.git`, Electron
launches require real framework evidence + `CFBundleExecutable` with no path separators and
`appArgs` rejects `--*-launcher`/`--*-cmd-prefix`/`--no-sandbox`/`--load-extension`/
`--disable-web-security`, `--allowed-domains` treats non-`http(s)` URLs as violations (with the
Electron local-app-roots file-URL exemption), POSIX children in their own process group, the
CLI path pinned (workspace-local shim refused as `policy-blocked`), the `--config` privileged-
flag gate, and the `DENIED_CHILD_ENV_VARS` env stripping (`PI_AGENT_BROWSER_FORWARD_ALL_ENV=1`
overrides). `bin/pi-setup-vendor --verify` reproduces the fork exactly.

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

**CLI re-baseline, 2026-07-30.** The pinned `agent-browser` moved 0.33.0 -> 0.33.1. The
release adds one flag, `--idle-timeout`, which this wrapper's argv grammar already listed,
and changes no command. It also changes a default that matters for long runs: the
`agent-browser` daemon now exits after **one hour** with no commands, where before it ran
until told to stop. A run that opens a page, works elsewhere for over an hour and comes back
finds a fresh daemon; tabs and transient state from the old one are gone unless the session
had a restore key. Headed, Safari/iOS and user-attached browsers are exempt.
`--idle-timeout 0` disables it, and `AGENT_BROWSER_IDLE_TIMEOUT_MS` still works.

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

First-party, not a fork. Steers Pi's own compaction toward a handoff brief: hook
`session_before_compact`, call Pi's `compact()` with focus instructions, provider
environment and a retry policy, then return the result — after merging the previous
compaction's file lists back into it. That last step is not cosmetic: Pi refuses to carry
file lists forward from a hook-produced compaction, so without it the accumulated
read/modified lists restart empty at every boundary.

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

Based on `pi-voice-stt@0.6.0`.

Re-vendored onto 0.6.0 on 2026-08-18. Upstream added named profiles, a profile switch
shortcut, Kitty keyboard fallback, and native local macOS bridge installation. The merge
kept the hardened endpoint/credential and recorder controls plus this fork's non-modal,
placeholder-based dictation UI and multi-key voice binding.

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

**Added here.** `keybind` accepts a list and matches literal characters as well as Pi key
ids, so dictation can be bound to both `alt+p` and the `π` that macOS composes for the
same chord, including the CSI-u form a Kitty-protocol terminal uses for it. See
[`KEYBINDINGS.md`](KEYBINDINGS.md).

**Rewritten here: the dictation UI.** The input box no longer changes colour, the
start/stop/sent toasts are gone, and the state lives where the text does — the cursor
becomes a slowly pulsing red dot while recording, and a `[⠏ transcribing]` placeholder
holds the transcript's spot while the provider works. Transcription stopped being a modal
wait: the key that ends a recording chooses insert (`alt+p`), send (`enter`) or queue
(the `app.message.followUp` key), any other key inserts and is then applied, and typing
continues around the placeholder. Sending or queueing takes the whole composer with it — the
placeholder holds the cursor's spot inside the message — and the result waits in a live
widget until the transcript arrives, so the model gets nothing until it does. A failure
becomes an error line and returns the text to the composer rather than losing it.

There is only ever one recording: a second press during the seconds a recorder can take to
start is ignored rather than opening a second microphone. Transcriptions, though, can
overlap, so each placeholder carries its own slot — a concurrent one reads
`[⠏ transcribing 2]` — and each transcript replaces its own marker by exact text. Upstream's
`output.submitOnStop` is dropped: it made the voice key send instead of insert, which now
has its own key. `PI_STT_FAKE_TRANSCRIPT` / `PI_STT_FAKE_FAIL` /
`PI_STT_FAKE_DELAY_MS` replace the provider with a fixed answer so this lifecycle can be
driven end to end without a microphone or an API call.

**Residual risk.** Anyone who can write `~/.pi/agent/stt.json` can still send your
microphone audio to an arbitrary HTTPS host by naming a credential explicitly, or run any
already-executable binary via `capture.ffmpegPath`. Both are the documented feature set; the
fix removed the *silent* variants, where a defaulted key followed a host you never named.
`install.sh` keeps that file mode `600` on Unix and `bin/pi-setup-doctor` checks it (skipped on Windows, where NTFS has no Unix modes).

## pi-process-monitor-safe

A hand-written rewrite of `pi-process-monitor@1.2.0`, imported into this repository with its
original commit history. It adds a watcher cap, kill-all, aggregated heartbeats, and safe
session shutdown with no persistence or restore. Not re-vendorable with
`bin/pi-setup-vendor`; maintained directly.

### Upstream 2.0.2 was reviewed and declined

2.0.0 rebuilds the extension around crash-safe persistence: logical watcher UUIDs, source
fingerprints, lifecycle revisions, cross-process leases validated against boot id and
process start, abnormal-restart quarantine, versioned checkpoints, and
`monitor_inspect` / `monitor_recover` / `monitor_gc` to operate it. This fork persists
nothing — watcher definitions never reach the session file, so nothing can be restored or
leaked across restarts. Adopting 2.0.0 would reverse that decision rather than upgrade it,
so the fork stays on its 1.3.0 review baseline. `vendor.json` records this as
`reviewedAgainst: "2.0.2"`, which is a different claim from `version` and suppresses the
drift note through that release only. Releases 2.0.1–2.0.2 migrate upstream's seven-source
persistent tool interface to a strict-schema-safe discriminated object. This fork has only
spawn, poll and tail, does not opt the tool into strict constrained sampling, and has none
of the structured probe/recovery placeholders involved in that bug, so no code was ported.
Revisit that schema if strict constrained sampling is enabled for this tool.

**One fix was ported: the per-tick poll timeout.** The fork's no-overlap guard had no
bound, so a poll child that never exited — a hung SSH, which is the case poll mode exists
for — held the guard forever and the watcher went permanently silent, with no error to
latch onto. A tick now gets `intervalMs - 1000` and is killed through the existing
process-group escalation (POSIX negative PID, `taskkill /T` on Windows), reported once through the existing failure latch.

Declined from 2.0.0, with reasons:

- **Suspension after N consecutive failures.** A suspended watcher strands an agent waiting
  on it, and this fork has no recovery path to un-suspend one. The existing latch already
  prevents notification storms.
- **Exponential backoff with jitter.** Retrying every interval means the watcher self-heals
  the moment a remote comes back. Up to five minutes of extra detection latency is a worse
  trade than some wasted cheap spawns on a multi-day run.
- **Poll confirmation and mutating-command quarantine.** The model already holds an
  unrestricted `bash` tool, so gating monitor commands moves no security boundary.
- **Structured process/file/SSH/HTTP probes and process receipts.** New surface area whose
  purpose is to serve the persistence model this fork does not have.

### Why a progress bar warns instead of matching

Matching is line-oriented. A process that redraws one line with carriage returns and never
emits a newline produces no complete line, so no pattern can match — the watcher is blind
while looking exactly like a watcher that is waiting. Spawn mode also grew that partial line
without bound.

Both modes now cap the partial line and emit **one** `NO LINE BREAK` event per watcher. The
alternative — treating `\r` as a line terminator — was rejected after costing it out:

- Spawn mode has no dedup, and the coalescer has a hard flush at `coalesceMs × 4` = 8s
  precisely so a steadily-matching process cannot postpone its ping. A bar redrawing ten
  times a second whose text happens to match would therefore emit **every 8 seconds** —
  about 450 turn-triggering wake-ups an hour, for the life of the run, on a setup whose
  whole purpose is multi-day autonomy.
- `maxLines` is 20, so each of those events would carry twenty near-identical copies of the
  same bar.
- It changes what counts as a line for every watcher that already works.

Over the cap, the text after the final carriage return is kept in preference to a raw byte
tail: that is what a terminal would be displaying, it is naturally small, and it means a
marker printed *after* a long bar still matches when its newline arrives. Under the cap
nothing is rewritten at all, so ordinary output reaches the matcher byte-for-byte.

## pi-setup-maintenance

First-party, skills only: no extensions, no tools, nothing loaded into a running session
beyond one skill description. It carries `update-pi-setup`, the procedure for updating Pi,
`agent-browser`, and each fork, plus what to re-review after an upstream merge and how to
roll back.

It exists because the failure mode is predictable: an agent told to "update pi" reaches
for `pi update`, which bypasses the version pin in `lib/versions.json`, is silently reverted by
the next install, and shows up later as drift. The skill puts the pinned path where an
agent will find it. `bin/pi-setup-doctor` now reports that drift directly, comparing the
installed Pi and `agent-browser` against the versions `lib/versions.json` pins.

## Startup labels

Pi labels an extension by the directory holding its index file, falling back to the bare
filename when the entry is not an `index.*` (`modes/interactive/interactive-mode.js:891`).
Upstream `pi-voice-stt` points at `src/index.ts` and upstream dynamic-workflows at
`extensions/workflow.ts`, so the startup listing read `src` and `workflow.ts`. Both forks
now use the `extensions/<name>/index.ts` convention the other three already followed, so
the listing identifies every extension by name. The installer compiles each TypeScript
entry to a sibling `index.js` in the same folder so Pi does not pay jiti transpile cost
on every startup, and the listing still uses the `extensions/<name>/` directory name.
The listing differs between the two full entrypoints — `pi` deliberately excludes the
workflow fork, `piwf` loads it:

```text
pi   (full, without dynamic workflows)
     [Skills]
       monitor, update-pi-setup
     [Prompts]
       /watch
     [Extensions]
       agent-browser, btw, context-handoff, monitor, voice-stt

piwf (full, with dynamic workflows — the historical `pi`)
     [Skills]
       monitor, update-pi-setup, workflow-authoring, workflow-patterns
     [Prompts]
       /watch
     [Extensions]
       agent-browser, btw, context-handoff, monitor, voice-stt, workflow
```

For voice-stt that entry is a one-line re-export; `src/` is still the implementation. For
dynamic-workflows the entry file moved into its own directory and its two relative imports
were repointed. Nothing else changed.

A stray upstream package is still distinguishable at a glance: Pi prefixes `npm:` and
`git:` sources with the package spec (`pi-voice-stt@0.6.0:src`) and leaves `local/`
sources bare, so anything showing a version prefix is not one of these forks.

The lean `p` wrapper disables extension and skill discovery, then explicitly loads only
`voice-stt`, `btw`, `context-handoff`, and the conditional `mlx` extension (plus its
prompt-removal helper). Browser and
monitor are in both full entrypoints (`pi`, `piwf`); workflow is full-profile-only and, of
the two full entrypoints, only `piwf` loads it. `bin/pi-setup-doctor` checks the `p`
allowlist and enforces that the workflow fork is absent from `pi` and present in `piwf`, so
an accidental addition or omission is install-fixable drift.

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

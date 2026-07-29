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

**Default changes.** `DEFAULT_AGENT_TIMEOUT_MS` is 15 minutes (was unbounded) and a run
defaults to 100 agents (was 1000). The 1000 ceiling is still reachable via
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

Based on `pi-agent-browser-native@0.2.71`. Only `dist/` is shipped, so the fixes are in the
compiled tree.

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

## pi-continue-safe

Based on `pi-continue@0.9.3`.

**Closed.** The package made zero `ctx.isProjectTrusted()` calls while honouring project
config, project prompt overrides and project `.pi/settings.json` — and asset content was the
one thing inserted *unescaped*, so a cloned repo could replace the system prompt of the
summarizer that receives your entire transcript. Every project-scoped input is now
trust-gated, failing closed when the host cannot report trust. The keys that could redirect
or silence a write — `agentGuidePath`, `agentGuideSyncMode`, `agentGuideOverwritePolicy`,
`agentGuideAllowOutsideProject`, `allowSymlinkedOutputDirectory` — are user-scope only, so a
*trusted* but hostile repo cannot pick an escaping path and suppress the confirmation.

Guide and artifact reads and writes are `realpath`-confined, refuse to follow a symlink, and
refuse `.git`. The guide read is `O_NOFOLLOW`, requires a regular file, and is size-capped,
so a guide symlinked to a FIFO or `/dev/zero` can no longer hang compaction. The state
machine can no longer wedge: the unguarded `await` in front of the resume dispatch is
wrapped, a watchdog force-settles a stuck event, and config readers degrade to defaults with
one warning instead of throwing on every request. A synthesis failure falls back to Pi's
native compaction instead of destroying the in-flight turn, and validation tolerates fenced
JSON and unknown extra keys. Compaction ownership is claimed by a request nonce rather than
"an event is active", so your manual `/compact` is no longer hijacked. Settings writes are
atomic (temp file + rename). Overwrite provenance is a content digest, so a file you edited
by hand still prompts.

**Behaviour you will notice.** Per-repo guide selection is gone by design — a project can no
longer set `agentGuidePath` or turn sync off for itself (`enabled: false` remains the
project-scoped escape hatch), and one warning per project names the ignored keys. A guide
symlinked outside the repository needs `agentGuideAllowOutsideProject`, for reading as well
as writing. New settings: `maxChainedContinuations` (10) and `maxChainedSynthesisCostUsd`
(5) bound automatic chaining that was previously unlimited; set `0` to restore.
`synthesisFailureFallback` selects the native-compaction fallback.

**Residual risk.** Content-level injection through the transcript remains possible by
design: hostile file or tool output inside the history can still steer `brief.forbid` or
`brief.next[0]`. The mitigation is structural labelling of untrusted-derived entries plus the
reworded resume prompt — not enforcement — so a model that ignores the label can still act
on an attacker's proposal. A parent-directory TOCTOU window remains between the containment
check and the write, because Node exposes no `openat`. One cosmetic item is unfixable from an
extension: when synthesis fails, Pi's own native summarizer still receives the original
`customInstructions` including the correlation marker, because the host keeps a private copy.

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
| `PI_AGENT_BROWSER_ALLOW_DIRECT_BASH` | Calling `agent-browser` directly from `bash` |
| `PI_CONTINUE_TRUST_PROJECT_CONFIG` | Project config and prompt overrides on a host that cannot report trust |
| `agentGuideAllowOutsideProject` | Reading and writing a guide whose realpath leaves the project |
| `allowSymlinkedOutputDirectory` | A deliberately symlinked `.pi` or `.pi/continue` |
| `PI_STT_ALLOWED_ENDPOINT_HOSTS` | Additional hosts accepted for a named vendor alias |
| `PI_STT_BRIDGE_ALLOW_REMOTE` | Binding the bridge daemon beyond loopback |
| `trustProjectLocalWorkflows` | Repo-local saved workflows and run records |
| `webFetchAllowedHosts` / `webFetchAllowPrivateNetwork` | `web_fetch` to loopback or private ranges |
| `worktreeIsolationFallback` | Continuing when `git worktree add` fails |

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

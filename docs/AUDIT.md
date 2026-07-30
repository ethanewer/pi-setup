# Extension security audit

Audit of every Pi extension in this setup, performed 2026-07-28 against the pinned
upstream releases. Each fork in `forks/` exists to fix the findings recorded here.

Pi extensions run in the agent's own process with the user's full permissions. They
can read any file the user can read, spawn processes, and make network requests. An
extension is therefore part of the trusted computing base, and a *model-callable* tool
inside one is reachable by prompt injection from any file, web page, or repository the
agent reads.

None of the four upstream packages is malicious. There are no install hooks, no
obfuscation, no telemetry, and no hidden network destinations in any of them. The
engineering quality is generally high. The recurring defect is a **trust-model
failure**: all of them treat project-local files as trusted input, and Pi's
project-trust prompt does not cover the paths they read.

## How Pi's project trust actually works

Two facts that make several findings below much sharper than they first look:

1. **Trust is inherited down the directory tree.** `ProjectTrustStore.getEntry` walks
   up ancestors until it finds an entry (`core/trust-manager.js:19-32`), so a single
   `"/Users/you": true` in `~/.pi/agent/trust.json` silently trusts every repository
   anywhere under the home directory. `bin/pi-setup-doctor` reports this.
2. **The trust prompt only gates three paths** — `.pi/settings.json`,
   `.pi/extensions`, and `.pi/skills` (`core/trust-manager.js:7-14`). It never gated
   `.pi/workflows/`, `.pi/agents/`, or `.pi/config/`, so for those an extension must
   perform its own `ctx.isProjectTrusted()` check. Three of the four did not.

## @quintinshaw/pi-dynamic-workflows 3.4.1

Note on line references: the extension entry point imports `../../src/*.js`, so `src/`
is the tree Pi actually loads. `dist/` is a compiled mirror reachable only through the
package `exports` field. Findings were located in `dist/` and fixed in `src/`.

### CRITICAL — zero-click remote code execution from a cloned repository

Chain, every link verified in the shipped code:

1. `workflow-paths.js:35` makes `resolve(cwd, ".pi/workflows/runs")` a first-class run
   store — inside the current working directory.
2. `run-persistence.js:120-137` reads every JSON file there with a bare `JSON.parse`
   and no schema validation of any field.
3. `usage-limit-scheduler.js:206-224` (`coldStartRearm`, called unconditionally at
   startup from `:132`) arms a timer for any run with `status:"paused"`,
   `pauseReason:"usage_limit"`, `autoResume !== false` — with no check that this
   process or this installation ever created that run.
4. On fire, `workflow-manager.js:873-879` takes the file's `script` field and executes
   it.

Clone a repository, `cd` into it, start Pi, and roughly sixty seconds later attacker
JavaScript runs as the user, with no prompt, no tool call, and no user action at all.
Pi's trust prompt does not cover `.pi/workflows/`, so no trust setting prevents it.

### CRITICAL — the `vm` realm is escapable, making `workflow` a permission bypass

`src/workflow.ts:1251` builds the script context from raw host closures (`agent`,
`log`, `parallel`, …). Inside the realm, `log.constructor` *is* the host `Function`, so
`log.constructor("return process")()` yields the host `process` and from there
`child_process`. Verified empirically in isolation.

The package's own comment at `src/workflow.ts:380-383` admits `vm` is not a security
boundary, yet `workflow` is registered as an ordinary model-callable tool whose
`script` parameter is free-form JavaScript. The model cannot run `bash` without the
host's approval flow, but it can run anything through `workflow`.
`DETERMINISM_BLOCKLIST` is a source-text regex, bypassed by `Date["now"]`.

### HIGH

- **Repo-supplied saved workflows shadow the built-ins.** `workflow-saved.js:23,34,98`
  reads `<cwd>/.pi/workflows/saved/*.json`, `saved-commands.js:96-99` registers each as
  a slash command, and `builtin-commands.js:105-111` gives a same-named saved workflow
  *precedence* over the built-in. A planted `code-review.json` hijacks `/code-review`.
- **Unattended subagents at extreme scale.** `agent.js:344,485` gives every subagent
  read + bash + edit + write with no UI and no approval path, and `excludeSubagentTools`
  is a name denylist only. Defaults (`config.js:5-13`): 1000 agents per run, no agent
  timeout, no token budget, background by default.
- **`README.md:277` is false.** It claims filesystem and network access "are
  unavailable inside the orchestration script", contradicting `:264` ("not a security
  boundary"). A user relying on line 277 would run untrusted scripts.

### MEDIUM

`web_fetch` is an unrestricted SSRF and exfiltration primitive (`web-tools.js:12-22,96`,
`redirect:"follow"`, no host filtering); unsanitized `runId` gives path traversal into
delete, read, and log-write paths (`run-persistence.js:42-47,174-188`,
`logger.js:46,59`); no `timeout` on `runInContext` lets `while(true){}` wedge the whole
Pi process (`workflow.js:830`); worktree slugs truncate to 32 characters so every agent
collides on one id and all but the first silently run in the *shared* working tree
(`worktree.js:11-16`); run state is written world-readable with full scripts, prompts,
and results and no redaction (`workflow-manager.js:768-812`, `fs-persistence.js:44-53`);
background subagent output is auto-injected into the main conversation and triggers a
turn (`task-panel.js:143-165`); `<cwd>/.pi/agents/*.md` become subagent system prompts
with no trust gate (`agent-registry.js:113,124`); plus an unhandled rejection
(`workflow-commands.js:72`), a per-session listener leak (`task-panel.js:386-421`), an
unbounded auto-resume retry (`usage-limit-scheduler.js:299-306`), an unbounded in-flight
drain (`workflow.js:886-897`), `git` argument injection in `/code-review`
(`builtin-commands.js:172-181`), tools force-reactivated every session
(extension entry point), destructive rewriting of submitted user input
(`workflow-editor.js:252-291`), and a pid-only lease check (`run-persistence.js:49-61`).

## pi-agent-browser-native 0.2.71

### HIGH

- **Shell execution of a repo-controlled config string.** `lib/config.js:60-70` runs
  `exec()` — a shell — on any credential value beginning with `!`. Project config is a
  valid source, and `index.js:478` defaults to *trusted* when the host does not expose
  `isProjectTrusted`. The guard that should stop this,
  `isProjectSafeCredentialValueForProvider` (`lib/config-policy.js:225-228`), is a stub
  that discards its `provider` argument and returns `true` for any non-empty string.
  Verified: no scope filter exists anywhere between project config and `exec()`.
- **`electron.appArgs` filters four flags.** `lib/input-modes/types.js:17` reserves only
  the `--user-data-dir` and remote-debugging switches, so `--gpu-launcher`,
  `--renderer-cmd-prefix`, `--no-sandbox`, `--load-extension`, and
  `--disable-web-security` pass through to `spawn` and Chromium executes the launcher
  string. `docs/ELECTRON.md:258` calls these "sanitized".
- **The Electron evidence gate is forgeable.** `lib/electron/discovery.js:154-174`
  requires only that two paths be *directories*, and `launch.js:138` joins an
  unvalidated `CFBundleExecutable` from the plist, so `../../../../bin/sh` escapes the
  bundle. `docs/TOOL_CONTRACT.md:397` claims the wrapper "does not blindly launch
  arbitrary executables".
- **`outputPath` is an unconfined arbitrary-file-write.** Schema is any non-empty string
  (`lib/input-modes/params.js:136`); `lib/orchestration/output-file.js:36-41` uses an
  absolute path verbatim with `mkdir -p` on the parent. Content is page-derived.
- **No argv allowlist.** `lib/runtime.js:551-564` rejects only shell operators and
  `--session-mode`; `--executable-path`, `--args`, `--init-script`, `--extension`,
  `--proxy`, and `--allow-file-access` reach the CLI verbatim. `command-policy.js` and
  `navigation-policy.js`, named as policy, gate none of it.
- **Project config text is injected into the system prompt** (`index.js:653-666`).
  Values are `JSON.stringify`'d, but the sentence is a repo-controlled instruction.
  `getTrustedBrowserExecutablePath` (`config-policy.js:387`) is misnamed: it applies no
  trust filtering at all.

### MEDIUM and LOW

`--allowed-domains` returns "no violation" for any non-`http(s)` URL and is only checked
after success against the current tab, so a redirect to `file://` reads clean
(`navigation-policy.js:52-62`); POSIX termination does not kill the process group, so
`agent-browser` descendants survive timeout and abort (`process.js:65-72`); the
executable is resolved through `PATH` with the full parent environment forwarded
(`process.js:58-64,169-185`); `bash-guard.js` is defeated by quoting and disabled by
either a package-development cwd or the phrase "via bash" in the last user message;
`index.js:449-462` parses ancestor `package.json` files with no `try`/`catch` during
extension load; signal-killed children are reported as clean exits
(`process.js:74-87`); session untracking ignores the namespace key (`index.js:178`);
and detached Electron children outlive a `SIGKILL`ed host (`electron/launch.js:262-274`).

### Verified good — preserved by the fork

Three network destinations only (Exa, Brave, loopback CDP); thorough redaction of URL
userinfo, `Authorization`, and `Cookie` headers (`lib/runtime.js:26-303`); ANSI and
control-character stripping before model-visible output (`lib/pi-tool-rendering.js:7-9`);
and ownership-verified `0700`/`0600` temp handling with liveness-checked cleanup that
refuses to signal a pid or remove a profile it cannot prove it owns (`lib/temp.js`,
`lib/electron/cleanup.js:80-88,153`). This is the best-engineered part of the package.

## pi-voice-stt 0.4.0

### HIGH

- **Provider aliases do not pin the vendor host.** `config/load-config.ts:220-228` only
  *injects a default* endpoint for `openai`/`groq`/`local`; at `:159` an explicit
  `provider.endpoint` overrides it while `apiKeyEnv` stays `OPENAI_API_KEY`.
  `secureEndpointFrom` (`config/endpoint.ts`) checks the scheme is HTTPS and that there
  is no userinfo — never that the host matches the named vendor. One config line sends
  microphone audio *and* the OpenAI key to any HTTPS host, and the UI still shows a
  normal transcription.
- **`capture.ffmpegPath` is arbitrary program execution from config**
  (`audio/ffmpeg-recorder.ts:35`, `index.ts:126`). No shell is involved, so there is no
  injection — but the named binary runs on the next dictation.
- **Gladia's `result_url` is server-controlled and receives the API key.**
  `providers/gladia.ts:10-17` takes it verbatim from the response and fetches it with
  the `x-gladia-key` header, bypassing `secureEndpointFrom` — the one unvalidated
  request target in the package.
- **Hot-mic race.** `core/dictation-controller.ts:213-220` checks `disposed` before and
  after config load but not after `await recorder.start()`. A shutdown in that window
  orphans a live `ffmpeg` holding the microphone, with the indicator suppressed.

Amplifier: the config is re-read on **every dictation** (`index.ts:37`), so any change
takes effect with no restart, and `~/.pi/agent/stt.json` shipped world-readable.
`install.sh` now sets it to `600` and `bin/pi-setup-doctor` checks it.

### MEDIUM and LOW

The cleanup pass defaults to `OPENAI_API_KEY` for *any* endpoint
(`config/load-config.ts:261`); `apiKeyFile` returns the entire file when it contains no
`=`, making it a general secret-read primitive (`secrets/resolve-api-key.ts:18`); two
`fetch` calls omit the `redirect:"error"` every other call sets
(`cleanup/openai-compatible.ts:25`, `audio/bridge-recorder.ts:50`); the optional macOS
bridge daemon **fails open** — no token means no authentication, and `POST /start` is a
CORS simple request, so a visited web page can switch on the microphone
(`tools/macos-bridge-server.mjs:20,55`); `capture.maxSeconds` is enforced only by a JS
timer that can silently never fire; a cancel during startup latches and silently drops
the *next* transcript (`core/dictation-controller.ts:197-201`); `$&` in a replacement
value expands as a substitution pattern and `\b` never matches accented keys, breaking
the shipped French locale (`core/replacements.ts:17-18`); and `keychain.ts:16` spawns
without an `error` handler, so a spawn failure can crash the host.

### Verified good — preserved by the fork

Zero runtime dependencies, no install scripts, no `eval`, no telemetry, keys never
logged, and audio staged in mode-`0700` `mkdtemp` directories with cleanup on every
path. The Keychain call is correct: absolute `/usr/bin/security`, argv array, no shell.

## pi-continue 0.9.3

### HIGH

- **No trust gate anywhere.** The package never calls `ctx.isProjectTrusted()` — zero
  occurrences — while honouring project config (`src/config.ts:219`), project prompt
  overrides (`src/assets.ts:19,29`), and project `.pi/settings.json`
  (`src/pi-settings.ts:67`). `promptOverridePolicy` defaults to `"project-override"`
  (`src/config.ts:55`), and asset content is the one thing inserted **unescaped**
  (`src/prompt.ts:29-41`). So a cloned repository can replace the *system prompt* of the
  summarizer model that receives the entire compacted transcript, and its output becomes
  the brief the resuming agent is told to treat as authoritative durable memory.
- **Symlink escape in the agent-guide path.** `src/project.ts:51-59` rejects `..` by
  string comparison with no `realpath` check, then `:93-104` does `mkdir -p` +
  `writeFile`. A repo containing `docs -> ~/.ssh` plus a config pointing at
  `docs/authorized_keys` writes model-authored content outside the project.
- **An unguarded `await` wedges the state machine permanently.** `index.ts:368-377`
  awaits two calls with no `try`/`catch` *before* the resume dispatch at `:403-405`, and
  by then the compaction-proof timeout has been cleared and no resume timer is armed. A
  repository containing a *directory* named `AGENTS.md` throws `EISDIR`, and the event
  stays `running` forever: every later `/continue` says "still resuming", and because
  ownership is claimed whenever an event is active, even manual `/compact` is hijacked.
- **Config readers throw on the per-request hot path** (`src/config.ts:152-159`,
  `src/pi-settings.ts:42-49`, called from `index.ts:192-194` with no `try`/`catch`). One
  stray comma disables the overflow guard on every request while spraying error toasts.
- **A synthesis failure costs the in-flight turn.** `src/runtime.ts:238` aborts *before*
  compacting, and `hasExactKeys` (`src/blocks.ts:67-72`) rejects fenced JSON or one
  extra field, so a model whim destroys a long turn with no compaction saved.
- **Unrelated compactions are hijacked.** `index.ts:198-200` claims ownership whenever
  any event is active, which lasts minutes, so a user's `/compact` during a resume
  spends another paid summarizer call and overwrites that event's state.

### Reassuring

Compaction **cannot lose session history on disk** — Pi only appends, and
`buildContextEntries` merely excludes entries from the live context, so raw entries stay
recoverable. The failures are context losses and state-machine wedges, not data loss.
This package also has the best prompt-injection defences of the four: every runtime data
block is tag-escaped, model output is schema-validated, and terminal escapes are
stripped before rendering. The fork keeps all of that intact.

## pi-process-monitor

Replaced earlier by the hand-written `forks/pi-process-monitor-safe`, imported into this
repository with its original commit history. It adds a watcher cap, kill-all, aggregated
heartbeats, and safe session shutdown with no persistence or restore. The unpatched
`pi-process-monitor@1.2.0` is no longer installed or referenced.

## Found while fixing

Three findings did not come from the original audit. They surfaced when adversarial
verifiers attacked the first round of fixes, and they are recorded here because each one
defeated a fix that looked correct.

- **The browser wrapper's privileged-flag gate was moot on its own.** Gating
  `--executable-path`, `--init-script`, `--proxy`, `--allow-file-access`, `--extension`,
  `--args`, and then `--config` still left the capability reachable with **no flag at
  all**: upstream `agent-browser` auto-discovers `./agent-browser.json` in its process
  working directory, and its own `--help` documents that project-level file as
  *overriding* user-level defaults. A repository that merely ships that file supplies
  `executablePath`, `initScripts`, `proxy`, and `allowFileAccess`. Confining the flags
  without also controlling the child's configuration discovery would have been security
  theatre.
- **Path confinement by string comparison is not confinement.** Both the browser fork's
  write-path policy and `pi-continue`'s guide-path check initially compared `resolve()`d
  paths, which a symlink inside the workspace walks straight through. Only a `realpath` of
  the deepest existing ancestor actually contains the write.
- **A regression repair can reopen the hole it was meant to work around.** Instructing the
  fix pass to "allow reading a symlinked agent guide by default" — to restore a legitimate
  dotfiles workflow — reopened the injection path in full: with default configuration in an
  untrusted repository, `AGENTS.md -> ~/.ssh/id_ed25519` fed that file into the summarizer
  prompt. Reading is not the safe half of a file operation when the content lands in a
  model's context. That instruction was mine, and the verifier caught it.

## Method

Findings were produced by four independent per-package audits and then re-verified by
hand against the shipped code before being fixed: the trust-inheritance behaviour, the
`vm` bridge-function escape, the stub credential check, the unconfined `outputPath`
write, the provider host-pinning gap, and the absence of any `isProjectTrusted` call
were each confirmed directly rather than taken from a report.

Fixing then took four rounds, because each round was adversarially re-reviewed by an
independent agent instructed to *refute* the fixes and to hunt for feature regressions,
rather than to confirm them. Round one closed most findings; verification found four
security gaps that had survived and one blocking regression. Round two closed those and
introduced two reopened holes of its own. Round three closed those. Findings were treated
as closed only with traced evidence, and many were settled by executing the code — a
differential harness for the microphone-orphan race, measured `ffmpeg` output for the
duration cap, a live exploit for the browser config discovery — rather than by reading it.

`docs/FORKS.md` records the per-fork outcome, including the residual risk that remains and
the capabilities that are now gated behind an explicit opt-in.

---
name: update-pi-setup
description: Update this machine's Pi installation, the pinned agent-browser, or any hardened extension fork, and verify the result. Use when Pi has a new release, when bin/pi-setup-doctor reports drift or a newer upstream, when asked to update pi or an extension, or before changing anything under ~/pi-setup.
---

# Updating this Pi setup

Everything is driven from the git repository at `~/pi-setup`. `install.sh` there is the
single source of truth: it pins the Pi and `agent-browser` versions, copies each fork
from `forks/` into `~/.pi/agent/local/`, rewrites the `pi`, `p`, and `agent-browser`
wrappers in `~/.local/bin`, and prunes stale npm copies of the extensions.

## Rules

1. **Never** run `pi update`, `bun add --global @earendil-works/pi-coding-agent`, or
   `pi package add` for these extensions. They bypass the pin, the next `./install.sh`
   silently reverts them, and `bin/pi-setup-doctor` reports the drift as a PROBLEM.
2. **Never** edit anything under `~/.pi/agent/local/`. That directory is install output.
   Edit `forks/<name>/` in the repository and reinstall.
3. Read the upstream changelog for breaking changes **before** bumping a version, not
   after. Extensions here use Pi's SDK deeply; a removed API is a real risk.
4. Finish every change with [Verify](#verify) and a commit. `bin/pi-setup-doctor` must
   exit 0.
5. Report only what you ran. Every line in a summary must correspond to a command whose
   output you saw in this session. If a check was skipped, say so; if it failed, say so.
   See [Reporting](#reporting). This rule exists because it was broken.

## Reporting

A summary that says "all verified" is the only evidence the user has. Treat overstating it
as the worst available outcome, worse than leaving the work unfinished, because it removes
the reason to look.

If a workflow did the work, **check the run for stage errors before writing the summary**:

```bash
/workflows status <runId>          # error=N is a failed stage, even when status=completed
```

A workflow reaching `status=completed` with `error=1` means one stage produced nothing.
`agent()` returns `null` there, and a later stage interpolating it receives the string
`null` without noticing. Guard it in the script rather than hoping:

```js
const implementation = await agent(`...`)
if (!implementation) throw new Error("implement stage produced no output; not publishing")
```

Never let a publish stage run behind an unchecked stage. A publish stage means commit, push, or install. This is
not hypothetical: run `configure-p-light-extensions-ms89ct6n-61zuep` lost its implement
stage after 31 minutes and ~1.16M tokens, the reviewer was handed `IMPLEMENTATION: null`,
and it committed and pushed anyway while reporting an unqualified list of passing checks.
The change happened to be correct. Nothing in the process established that.

## 1. Find out what is out of date

```bash
cd ~/pi-setup && bin/pi-setup-doctor
```

Every section, in the order it prints. Only "Upstream releases" is advisory. Every other
section can emit a PROBLEM and fail the exit code.

| Section | What a finding means |
|---|---|
| Forks: repository vs installed | An installed copy no longer matches `forks/`. Re-run `./install.sh`. |
| Pi settings | `settings.json` does not load a fork, or still loads the unpatched npm package that would shadow it. |
| Configuration hygiene | `stt.json` is not mode 600, or `trust.json` trusts a directory that every repository sits under. |
| Compiled mirrors | `pi-dynamic-workflows-safe`'s `dist/` no longer matches its `src/`. Both are reachable through the package exports, so a stale `dist` exports code nobody audited. Run `npm run build` in that fork. |
| Keybindings and the p profile | An agent directory is missing a binding from `config/keybindings.json`, or the `p` profile is gone. Re-run `./install.sh`. See `docs/KEYBINDINGS.md`. |
| Retired and unknown local packages | A package on disk that `vendor.json` does not know about. It is dead code that can still be loaded if it is re-added to settings. |
| Pi and agent-browser | Installed version differs from the pin in `install.sh`. Something bypassed the installer. |
| Compaction settings | `reserveTokens` outside the band in `config/compaction.json`, or compaction disabled. Too small is the common one: Pi only checks the threshold *after an agent run finishes*, so a reserve that covers one reply but not one whole run lets context overshoot the window. Too large stalls the summarization call. Note the reserve is slack, not a bound. A long enough run passes any threshold, and no setting or extension prevents that. See [`LONG_RUNS.md`](../../../../docs/LONG_RUNS.md). |
| Upstream releases | npm has a newer release than this repository pins. A note, not a problem: upgrading is a deliberate act. |

`vendor.json` is the machine-readable record of which upstream release each fork is
based on. `docs/FORKS.md` says what each fork changes and why, and is what to re-check
after an upstream merge.

## 2. When the doctor reports a PROBLEM

Try the mechanical repair first. It reinstalls from `forks/`, which is the fix for a drifted
install, a settings file that lost a package, a missing keybindings file, a missing `p`
profile, and a version that no longer matches the pin:

```bash
bin/pi-setup-doctor --fix
```

It re-runs the whole report afterwards, so a clean exit means the problem is gone. It will
not touch anything that needs a decision, and says so rather than pretending. Those cases:

| PROBLEM | What to do |
|---|---|
| `trust.json trusts <path>` | Remove that key and re-approve individual repositories. Trust inherits down the tree, so a home-wide entry trusts every repository you ever clone. |
| `compaction.reserveTokens is …` / `compaction is disabled` | For a reserve below the floor, `--fix` reinstalls and applies `config/compaction.json`. For a hand-set value that is too large, or `enabled: false`, edit `~/.pi/agent/settings.json`. Deleting the key lets the installer reapply the policy. See [`LONG_RUNS.md`](../../../../docs/LONG_RUNS.md). |
| `<name> is installed at … but is not in vendor.json` | A retired package. Confirm it is not wanted, then `rm -rf` that directory. `--fix` will not delete for you. |
| `stt.json is not valid JSON` / `no usable keybind` | Fix the file by hand; `install.sh` only rewrites the keys it manages, so a syntax error survives a reinstall. |
| A fork does not reproduce from its patch (`bin/pi-setup-vendor --verify --all`) | Someone edited `forks/` without regenerating. Run `bin/pi-setup-vendor --regenerate-patch <fork>` and review the diff. |

If the problem is a defect in an extension rather than a broken install, that is a code
change: fix it in `forks/<name>/`, regenerate the patch if that fork has one, add a test
under `tests/` when the logic is pure, and follow [Verify](#verify).

## 3. Update Pi itself

```bash
cd ~/pi-setup
npm view @earendil-works/pi-coding-agent version          # what is available
```

Before bumping, read the changelog for that release at https://pi.dev/changelog, or after
installing, `~/.bun/install/global/node_modules/@earendil-works/pi-coding-agent/CHANGELOG.md`.
Look specifically at **Breaking Changes** and anything touching the extension API, the
SDK (`createAgentSession`, `ResourceLoader`, `SessionManager`, `ExtensionAPI`),
compaction hooks, or skills, then grep the forks for whatever it names. For example,
0.83.0 removed several TypeBox APIs:

```bash
grep -rn "Type\.Base\|Type\.Awaited\|Type\.Promise\|Value\.Mutate" --include="*.ts" --include="*.js" forks/ | grep -v node_modules
```

Then:

1. Set `PI_VERSION` in `install.sh`.
2. Update the version table in `README.md`.
3. `./install.sh`. Use `PI_SETUP_SKIP_BROWSER_INSTALL=1 ./install.sh` to skip the Chrome
   check while iterating.
4. [Verify](#verify), then commit.

## 4. Move a fork onto a newer upstream release

Four forks track an upstream. Three can be re-vendored mechanically because they have a
patch file: `pi-voice-stt-safe`, `pi-agent-browser-native-safe`, and
`pi-dynamic-workflows-safe`. `pi-process-monitor-safe` tracks
`pi-process-monitor` by hand, with no patch, so upstream changes are ported deliberately
and the decision recorded in its `vendor.json` note.

For the three with a patch:

```bash
bin/pi-setup-vendor <fork> <new-version>
```

It downloads pristine upstream, applies `patches/<pkg>@<old>.patch`, replaces
`forks/<fork>` on success, updates `vendor.json`, renames the patch file, and
regenerates it. **If the patch does not apply cleanly** it stops and leaves a partially
patched tree with `.rej` files in `.vendor-tmp/`, printing the exact commands to finish
by hand.

After any re-vendor, treat the hardening as unverified until you have re-checked it:

1. `git diff -- forks/<fork>`. Read all of it.
2. Re-read the fork's section in `docs/FORKS.md` and confirm each fix still exists in the
   merged tree. Upstream refactors move code; a fix can survive `patch` and still be
   bypassed by a new code path that reaches the same sink.
3. Read the upstream changelog between the two versions for new entry points.
4. `bin/pi-setup-vendor --verify <fork>`. The patch must reproduce `forks/<fork>` byte
   for byte.
5. Update the table in `README.md`. `vendor.json` is the machine-readable record and
   `bin/pi-setup-vendor` already updated it.
6. `./install.sh`, then [Verify](#verify).

If you hand-edit a fork instead, regenerate its patch so it stays the reviewable record:

```bash
bin/pi-setup-vendor --regenerate-patch <fork>
bin/pi-setup-vendor --verify <fork>
```

`pi-process-monitor-safe` is hand-maintained with no patch file; port upstream fixes
manually and record what you decided in its `vendor.json` note.

### Declining a release

A hand-maintained fork may legitimately refuse an upstream release. `pi-process-monitor`
2.0.0 is built on crash-safe persistence: logical UUIDs, cross-process leases, restart
quarantine, recovery tools. This fork persists nothing by design, so adopting it would
reverse the fork's central decision rather than upgrade it.

When that happens, do not leave the drift note firing forever; a note that never clears
teaches the reader to skip notes. Instead:

1. Read the release properly and port anything that fits. From 2.0.0 that was one fix: the
   per-tick poll timeout, because the fork's no-overlap guard was unbounded and a hung SSH
   child silenced a watcher permanently.
2. Set `reviewedAgainst` to that version in `vendor.json`, keeping `version` as what the
   fork is actually built on. The two fields are different claims and must not be conflated.
3. Write the reasoning into the `note`: what was ported, what was declined, and why for
   each. The next reader should not have to redo the analysis.

The doctor then reports `reviewed and declined` instead of drift, and starts reporting
again at the next release, because `reviewedAgainst` will no longer equal latest.

## 5. Change a first-party package

`pi-context-handoff`, `pi-btw-side`, `pi-setup-maintenance`, and `unslop` have no upstream. Edit
them directly, bump `version` in both `package.json` and `vendor.json` if the change is
worth marking, then `./install.sh`.

`config/keybindings.json` is the other tree the installer owns: it is merged into
`~/.pi/agent/keybindings.json` and the `p` profile's copy, touching only the ids listed in
it. Edit it there, never in the agent directory. `docs/KEYBINDINGS.md` records why each id
is remapped and how to measure a key with `bin/pi-setup-keyprobe`.

Typecheck before installing. Pi runs TypeScript without checking it, so a type error
becomes a runtime failure inside a session:

```bash
dir="$(mktemp -d)" && ln -s "$HOME/.bun/install/global/node_modules" "$dir/node_modules"
cat > "$dir/tsconfig.json" <<JSON
{
  "compilerOptions": {
    "target": "ES2023", "module": "ESNext", "moduleResolution": "bundler",
    "allowImportingTsExtensions": true, "strict": true, "noEmit": true,
    "skipLibCheck": true, "types": ["node"], "paths": { "*": ["./node_modules/*"] }
  },
  "include": ["$HOME/pi-setup/forks/<pkg>/**/*.ts"]
}
JSON
(cd "$dir" && bunx tsc --noEmit)
```

The `node_modules` symlink and `types: ["node"]` are both load-bearing: Pi supplies its
packages at runtime and they are not dependencies of this repository, so without them tsc
cannot resolve `@earendil-works/*`, `node:fs` or `process`, and reports errors that are
artefacts of the invocation rather than defects in the code.

## 6. agent-browser is pinned to the fork's baseline, on purpose

`AGENT_BROWSER_VERSION` in `install.sh` is not "whatever npm has latest". The
`pi-agent-browser-native-safe` wrapper is validated against one specific CLI release.
`docs/SUPPORT_MATRIX.md` in that fork names it as the capability baseline. Raising it is
a re-baseline job. Note that the fork vendors only `dist/`, `scripts/` and `docs/`. The
`npm run verify` gates its own SUPPORT_MATRIX.md describes live in upstream's repository,
not here, so re-running them means working from an upstream checkout at the target
version. What can be done in this repository is re-reading
`docs/COMMAND_REFERENCE.md` and `docs/SUPPORT_MATRIX.md` against the new CLI's `--help`,
and re-checking the artifact-path guards that hard-code command prefixes. `bin/pi-setup-doctor` will keep reporting the newer release as a note until
then; that note is expected, not a defect.

## Verify

Run all of this after any change. It is cheap except for the model calls in the last two.

```bash
cd ~/pi-setup
bin/pi-setup-doctor              # must exit 0
bin/pi-setup-vendor --verify --all   # every patch still reproduces its fork
bun test tests/                  # pure logic of the first-party extensions
tests/fork-suites.sh             # the suites that ship inside the forks (84 tests)
tests/smoke.sh                   # installed setup: tools, bash, /btw, browser, workflow
tests/tui-btw.sh                 # TUI-only: the /btw side view and escape
```

`tests/fork-suites.sh` runs `forks/pi-process-monitor-safe/test/`. A bare `bun test` from
the repository root collects those files too but they error, because that fork has no
`node_modules`; the script links Bun's global tree in for the run and removes the link
after. Use the script, not a bare `bun test`.

After changing `install.sh` or `bin/pi-setup-doctor`, also run:

```bash
tests/linux-install.sh           # needs Docker; push first, it tests the published install.sh
```

Everything else here runs on macOS, so Linux-only breakage is invisible without it. That means GNU vs BSD `stat`, a
missing `unzip`, or assuming `node` exists. That class of bug has
shipped before.

`tests/smoke.sh --quick` skips the browser and workflow runs while iterating. The voice
UI has a test seam for the paths a script cannot reach otherwise:
`PI_STT_FAKE_TRANSCRIPT`, `PI_STT_FAKE_FAIL` and `PI_STT_FAKE_DELAY_MS` replace the
provider with a fixed answer, so the placeholder lifecycle can be driven without a
microphone or an API call.

Then start `pi` and `piwf` once interactively and confirm each startup listing is intact.
`pi` must NOT list the workflow extension or workflow skills; `piwf` must list both:

```text
pi   (must omit workflow and the workflow skills/commands)
     [Skills]
       monitor, unslop, update-pi-setup
     [Prompts]
       /watch
     [Extensions]
       agent-browser, btw, context-handoff, monitor, voice-stt

piwf (must include workflow)
     [Skills]
       monitor, unslop, update-pi-setup, workflow-authoring, workflow-patterns
     [Prompts]
       /watch
     [Extensions]
       agent-browser, btw, context-handoff, monitor, voice-stt, workflow
```

A fork that failed to load is **silently absent** from that listing rather than raising
an error, so check the names rather than assuming success.

## Auditing the extensions for defects

The doctor checks that the installation is intact; it says nothing about whether the code
is correct. For that, [`docs/AUDIT-EXTENSIONS.md`](../../../../docs/AUDIT-EXTENSIONS.md)
records how the 2026-07-30 audit was run. One agent per package hunted bugs and UX
defects, and each finding went to a second agent instructed to refute it. The same file records what it
found, and which findings were deliberately not fixed. Repeat it the same way after a
large change, and update that file with what the next pass finds.

## Commit

Commit to `~/pi-setup` and push to `origin main`. Say in the message what upstream
version moved, what the changelog's breaking changes were, and what verification ran.
The repository's history is the audit trail for the hardening, so a version bump with no
review notes is worse than no bump.

## Rollback

Every version is pinned in `install.sh`, so rolling back is a git operation plus a
reinstall:

```bash
cd ~/pi-setup
git revert <commit>     # or: git checkout <good-commit> -- install.sh forks/ patches/ vendor.json config/
./install.sh
bin/pi-setup-doctor
```

## Exporting session traces

`bin/convert-pi-traces` converts local pi session traces into a shareable
HF dataset (`eewer/pi-trace-cache`), filtering out OpenAI/Anthropic/test models
and replacing API keys with deterministic fakes. It is standalone (not run by
`install.sh`, not checked by `pi-setup-doctor`); see the "Exporting traces to a
dataset" section in `README.md` and `bin/convert-pi-traces --help` for details.

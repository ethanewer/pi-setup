# Auditing the extensions

`bin/pi-setup-doctor` checks that the installation is intact. It says nothing about whether
the code is correct. This file records how the extensions were audited for defects, what
that found, and what was left.

## How the 2026-07-30 pass was run

One agent per package — all seven in `vendor.json` — each told to read the code that
actually runs, starting from the entry point in `package.json`'s `pi` field, and to report
correctness bugs and UX/TUI defects with a file, a line, and a concrete failure scenario.
Security was explicitly out of scope: [`AUDIT.md`](AUDIT.md) covers that, and re-litigating
it wastes the pass.

Every finding then went to a second agent whose instruction was to **refute** it: open the
file, follow the path, and default to "not real" when the failure could not be demonstrated
from the code. That framing matters more than the finding pass — a confident, wrong finding
costs a maintainer a real investigation. Two findings died there, one of them because the
auditor had misread Pi's own compaction prompt.

Findings ranked by how likely a user is to hit them, not by how clever they are.

## What it found

45 findings, 43 confirmed after refutation: 5 high, 14 medium, 24 low. Every high and
medium was fixed the same day (commits `018d81a`, `8da17ce`, `2f14145`). The pattern worth
remembering: three of the five highs were in code written in the previous two days, and one
of them — workflow agent retries resolving to 0 — had been documented in
[`LONG_RUNS.md`](LONG_RUNS.md) as a guarantee for a week while being false in practice.
New code and confident documentation are where this pass paid for itself.

## Deliberately not fixed

These are the low-severity findings left in place. They are real; they are recorded so the
next pass does not spend time rediscovering them, and so anyone hitting one knows it is
known rather than unnoticed.

| Package | Where | Finding |
|---|---|---|
| `pi-agent-browser-native-safe` | `temp.js:369` | Persistent spill artifacts accumulate forever under the pi session directory |
| `pi-agent-browser-native-safe` | `output-file.js:67` | A refused outputPath write is invisible to the model when args contain --json |
| `pi-agent-browser-native-safe` | `process.js:412` | stdout/stderr tails are decoded per chunk, so multi-byte characters split across a read become U+FFFD |
| `pi-btw-side` | `view.ts:269` | Long error notices are hard-truncated at the terminal width, hiding the actionable half |
| `pi-btw-side` | `view.ts:247` | Footer says "shift+↓ to follow" but shift+↓ scrolls exactly one row |
| `pi-btw-side` | `view.ts:298` | truncate() slices ANSI-colored text by raw string index |
| `pi-btw-side` | `view.ts:87` | Side view ignores the user's outputPad / hideThinkingBlock / codeBlockIndent settings |
| `pi-btw-side` | `view.ts:281` | Terminals 10 rows or shorter render a 40-row view, pushing the composer off screen |
| `pi-context-handoff` | `index.ts:96` | notifyOnFallback: false does not suppress the empty-brief warning |
| `pi-context-handoff` | `index.ts:71` | getApiKeyAndHeaders result is used without narrowing its ok discriminant |
| `pi-dynamic-workflows-safe` | `workflow-capability-contract.ts:465` | Model-facing capability contract and README still state a 15-minute agent timeout |
| `pi-dynamic-workflows-safe` | `workflow-ui.ts:1516` | Undocumented destructive single keys (x stop, r restart, s save) are live in the detail pager |
| ~~`pi-process-monitor-safe`~~ | ~~`runtime.ts:286`~~ | **Fixed 2026-08-02.** Spawn's partial-line buffer was unbounded, and a carriage-return-only process could never match. Ranking it low was wrong: the workload on `mk` is EvalScope/Slurm, whose output is full of carriage returns. Both modes now bound the partial line and emit one `NO LINE BREAK` warning, so a blind watcher is visible instead of silent. Splitting on `\r` was rejected — see [`FORKS.md`](FORKS.md#pi-process-monitor-safe). |
| `pi-process-monitor-safe` | `runtime.ts:558` | timeoutSeconds discards already-matched buffered output instead of flushing it |
| `pi-process-monitor-safe` | `extension.ts:186` | Message renderers hardcode paddingX=0, ignoring the outputPad option pi passes in |
| `pi-process-monitor-safe` | `extension.ts:368` | /monitor --file accepts an unreadable path and still reports the watcher as running |
| `pi-setup-maintenance` | `SKILL.md:31` | Only 4 of bin/pi-setup-doctor's 7 sections are documented, and the 3 missing ones emit PROBLEMs |
| `pi-setup-maintenance` | `SKILL.md:107` | Skill has no path for keybindings, now a second install-managed source tree |
| `pi-setup-maintenance` | `SKILL.md:172` | Rollback recipe omits patches/, leaving vendor.json pointing at a renamed patch file |
| `pi-setup-maintenance` | `SKILL.md:148` | Startup-listing sample does not match what pi actually prints |
| `pi-setup-maintenance` | `pi-setup-doctor:257` | Doctor's upstream note suggests a re-vendor command that always fails for pi-process-monitor-safe |
| `pi-voice-stt-safe` | `dictation-controller.ts:104` | Cancel is global, so it discards the wrong transcript when two transcriptions overlap |
| `pi-voice-stt-safe` | `index.ts:209` | Voice-sent messages skip pi's submit pipeline: no editor history, and a leading slash is not executed |
| `pi-voice-stt-safe` | `index.ts:48` | Dead state and unused parameters left behind by the UI rewrite |

Two were fixed by hand because they sat in files being edited anyway. One more is a
documented limitation rather than a defect: the caret jumps to the end of the prompt after a
transcript is delivered, because Pi exposes no public way to restore a cursor position and
reaching into its private state is what made earlier extensions fragile.

A second entry on that list — `pi-process-monitor-safe`'s test suite needing `bun install`
in that fork — has since been resolved by [`tests/fork-suites.sh`](../tests/fork-suites.sh),
which borrows the dependencies from Bun's global tree. Those 84 tests had never run when
this pass was made, which is worth remembering when reading the monitor findings below: they
came from reading the code, with no suite to check them against.

## Packages added since that pass

`pi-context-handoff` post-dates the 2026-07-30 pass, so it has not been through it. Its
halves carry unit tests for their decision logic
([`tests/resume.test.ts`](../tests/resume.test.ts),
[`tests/fold.test.ts`](../tests/fold.test.ts)) and were verified end to end against a live
provider, which is more than the audited packages had at the time — but tests written by
the author of the code are not an adversarial read, which is the whole point of the pass.
Include it in the next one, and give the fold half the harder look: it rewrites what the
model sees on every call, so a defect there is a defect in every request rather than in
one feature.

## Repeating it

Run it after any large change. The shape that worked: audit per package, refute every
finding, fix highs and mediums, record the lows here. Update this file with what the next
pass finds — including anything in this table that turns out to matter more than it looked.

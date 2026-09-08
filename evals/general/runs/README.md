# Run recipes

Every script here produced something in the published dataset. They live in the
repository because until v3.6 they existed only in untracked scratch outside it,
which meant the harness invocations behind 4,710 records were not recoverable from
a clone.

## The harness

`harbor-requirements.txt` pins the harness itself. Nothing else in this repository
did, and it is not installed by anything here: it lives in a uv-managed venv
outside the repo. Two harbor versions exist on the machine that produced these
records and their CLIs are incompatible — 0.18.0 takes `--env`, 0.22.0 was used for
every v3.x run — so an unpinned harness produces trials that do not compare with
the published ones. Recreate it with:

```
uv venv --python 3.12.13 /path/to/venv
uv pip install --python /path/to/venv/bin/python -r runs/harbor-requirements.txt
```

That was run and checked rather than assumed: a fresh venv built from the lockfile
matches the one that produced the published records package for package -- 89 in
each, none missing, none extra, no version differences -- and `harbor run --help` is
byte-identical between the two.

Every script assumes `HARBOR`, `EVAL` and `OUT` near the top, `PYTHONPATH` pointed
at `evals/general/agents` for the `p_agent:PAgent` harness, and credentials sourced
from an env file. None of them contains a key. `p_agent.py` is the only agent that
lives in this repository; `oracle`, `nop`, `terminus-2` and `claude-code` ship with
harbor.

## The four operations that matter

| Operation | Script | What it establishes |
|---|---|---|
| Oracle census | `run-v35-pinverify.sh` | Every task's own `solution/solve.sh` under harbor's `oracle` agent, one trial each, no model and no inference. A task whose reference solution cannot earn reward 1 is broken regardless of what any agent scored. |
| Negative control | `run-v34-negative.sh` | Every task under harbor's `nop` agent, whose `setup()` and `run()` are both `pass`, so the verifier grades a pristine container. All must score 0. The census cannot substitute: a verifier that always writes 1 passes it at 785/785. |
| Six-pair re-run | `run-v35-rerun.sh` | Agent rollouts for every harness/model pair over a task list, one job per pair, launched concurrently. |
| Corpus re-collection | `collect-t2-full.sh`, `build-v38-overlay.sh`, `build-v38-artifact.py`, `build-v39-overlay.sh`, `build-v40-overlay.sh` | Re-collects every record for one harness from the trial named in its own published `source_trial`, then diffs the result against what is published on content bytes rather than message counts. Use when a detector heuristic has already been trusted once and was wrong. |
| Infrastructure retry | `run-v38-llm-stalls.sh`, `run-v38-harbor-gasket.sh`, `run-v39-stalls.sh`, `run-v39-cc-fixed.sh`, `run-v39-cc-retry.sh`, `run-v40-noassistant.sh` | Re-runs trials that never measured anything: an agent that timed out inside `_query_llm` having issued no command, or one killed by the tmux server vanishing. Distinct from a legitimate timeout, which is a real result and is not re-run. |
| Transcript recovery | `publish-v37.sh` | Re-collects records from raw trials already on disk, using `--overlay` instead of `--job`, when a collector bug published a lossy transcript. Verifies rewards are unchanged before assembling. |
| Publish | `publish-v310.sh` |
| Task repair | `run-v40-hollow-notch.sh` | Re-runs **all** pairs for a task whose environment was changed, not only the pairs that were broken. Leaving the unaffected pairs on the old task would compare a different task against the rest. |

Two failure modes look identical in a reward file and are not. `check_agent_actually_ran.py`
is the gate that separates them, and `build-v39-overlay.sh` runs it over exactly the trials
about to be published, stopping the build if any of them never reached the model.

- **Never measured.** The provider did not answer, or the harness died before the agent
  started. The trial burned its budget and scored 0 under TIMEOUT_FAIL, charging an outage
  to the model. Re-run it; the zero is not a result.
- **Legitimate timeout.** The agent worked and did not finish inside the task's budget.
  The zero is a real result. Do not re-run it, because re-rolling only failures moves the
  scoreboard in one direction.

Count turns, not token accounting. claude-code reports `input_tokens` and `total_cost_usd`
only in its final result event, which never lands when harbor kills the CLI on an agent
timeout, so a trial that did 58 real turns and 25 tool calls reports zero usage. The first
version of the gate used those fields and wrongly condemned four valid runs, three of which
had passed.

Per-pair environment differs and is easy to omit. claude-code reaches OpenRouter through
`ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL`, which `run-all.sh` exports; pi and terminus-2
take an `openrouter/`-prefixed model path instead. Omitting the two exports makes
claude-code return one synthetic message and exit 1, and every trial fails identically —
indistinguishable from a model that tried and lost. `run-v39-cc-fixed.sh` records that
incident, and the invalid job is kept as `v39-cc-glm-stalls-INVALID-noenv/` with an
`INVALID.md` rather than deleted. Chains `tools/publish_version.sh`: rescore, collect, assemble, upload, then read the tree back through the paginated Hub endpoint and compare counts. |

Concurrency is a real parameter, not a detail. The oracle census at twelve parallel
builds failed twenty tasks with `apt-get` exit 100 because the Debian mirrors
throttled the simultaneous fetches — including `v1-skill-telnet`, which installs
nothing but telnet and builds fine alone. At five concurrent builds the same sweep
passed 784 of 785. The six-pair re-run at thirty concurrent trials killed two
terminus-2 sessions mid-rollout with `tmux send-keys` returning 1.

## Re-running a task across all six pairs

`run-v35-rerun.sh` reads task names from `/tmp/v35_rerun_tasks.txt`, one per line,
and launches six jobs — `pi` and `terminus-2` against both models through
OpenRouter, `claude-code` against both through OpenRouter's Anthropic-compatible
endpoint. That endpoint needs `ANTHROPIC_API_KEY` and `ANTHROPIC_BASE_URL` exported
and the **bare** model slug, because harbor passes the whole `-m` string through as
`ANTHROPIC_MODEL`; the other two harnesses take the `openrouter/`-prefixed form.
`claude-code` also needs `--agent-setup-timeout-multiplier 4 -r 2
--retry-include AgentSetupTimeoutError`.

A repaired task must be re-run for **all six** pairs, not only the ones that failed.
Re-running just the failures re-rolls the dice for losses and never for wins, which
biases the scoreboard upward. `tools/publish_version.sh --require-rerun TASK`
enforces this: it dies unless every pair has a freshly collected record, because a
repaired task's old records are scoreable and therefore invisible to the
completeness and binarity gates.

## Retrying a trial that died on the harness

A trial that fails on infrastructure must be retried, not scored. Only an agent
timeout earns the documented `TIMEOUT_FAIL` zero; `collect_task_records.py` refuses
to score anything else and names the trial. Move the dead trial directory aside
rather than deleting it, re-run that task for that pair under a distinct job name,
and list both jobs in the publish spec with the retry last so it overrides.
`run-v34-rerun.sh` and the `v34-t2-glm-retry` job in `publish-v34.sh` are a worked
example; the moved-aside directories keep a README saying why they are not in the
published tree.

## Supporting scripts

- `build-bases.sh` — builds the three `bench-base:*` images from `bases/*.Dockerfile`.
  Task Dockerfiles `FROM` those tags, so this has to run first on a fresh machine.
- `disk-keeper.sh` — prunes build cache older than an hour when free space drops
  below 90G, and exits when a named census finishes. A full-suite census rebuilds
  every task image and grows the cache faster than it completes.
- `run-v34-fullsweep.sh`, `run-v34-postcensus.sh`, `run-v34-sweep.sh`,
  `run-v34-verify.sh` — the censuses and repair verifications behind v3.4, kept
  because the commit messages cite their job directories.
- `run-v34-amberdial.sh`, `run-v34-fixbatch5.sh` — single-task and small-batch
  oracle checks used while diagnosing individual repairs.
- `run-v37-driftcanyon.sh` — re-runs one task for the two terminus-2 pairs. Used when a
  record's raw trial directory is gone and the published transcript cannot be
  recovered from disk, so the trial has to be produced again.
- `publish-v33.sh` … `publish-v310.sh`, `finalize*.sh`, `assemble_v31.py` — the
  per-version publish recipes. `publish_version.sh` in `tools/` superseded the
  `finalize`/`assemble` pair; the older ones are kept because the published
  summaries name them as their own provenance.
- `run-v31.sh`, `run-all.sh`, `run-claude.sh`, `run-v33*.sh`, `smoke.sh`,
  `catchup.sh`, `archive.sh`, `run-orig-oracle.sh`, `run-oracle-sample.sh` —
  historical, from earlier versions.

## What is deliberately not here

The trial outputs themselves. `jobs/` holds every harbor trial directory — agent
transcripts, verifier logs, `result.json` — and runs to tens of gigabytes per
version. The four files per record that the dataset contract requires are published
to Hugging Face; the rest is scratch. The published `summary.json` names the job
directory each record was collected from, so a record can be traced back to a trial
on the machine that ran it but not reconstructed from the repository alone.


## A task can break the agent instead of the task

Two of the three harnesses are *installed* agents: their CLI runs inside the task
container and calls the LLM API over the network from there. Anything a task does to the
container's network or name resolution therefore happens to the agent, not only to the
work under test.

`hollow-notch` fragmented `/etc/nsswitch.conf` to `hosts: files`, removing the dns
fallback. Inside that container `curl` fails with `Could not resolve host:
openrouter.ai`. claude-code retried ten times and gave up with `UnknownApiError`, leaving
one synthetic message and no real assistant turn, at $0.000 and 0 output tokens; pi left
four assistant messages with null content. Four of six pairs scored 0 without making a
single model call. terminus-2 was immune because harbor drives its tmux session from the
host.

The tell is a reward of 0 with **no API spend and no output tokens**, clustered on one
task across every installed-agent pair. `check_agent_actually_ran.py` reports exactly
those counters. A task-side cause is also reproducible: re-running does not help, and the
same task fails the same way on two different models, which is what distinguished it from
the provider-outage window that produced the nineteen stalled trials in v3.8 and v3.9.

When a task's environment changes, re-run **all** pairs for it. The unaffected pairs'
existing records describe the old task.

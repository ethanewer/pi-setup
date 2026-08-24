# general-agent-bench

A benchmark of **general coding-agent ability**, built on
[harbor](https://github.com/harbor-framework/harbor). Tasks are derived from
`../skills.json` (76 skill items).

## Structure

```
tasks/                  one Harbor task per directory (see specs/plan.json)
  <name>/task.toml      harbor task config
  <name>/instruction.md the prompt the agent receives
  <name>/environment/   Dockerfile (+files/) — container the agent works in
  <name>/solution/      solve.sh oracle solution
  <name>/tests/         test.sh verifier (writes /logs/verifier/reward.txt)
agents/p_agent.py       custom Harbor agent reproducing the local `p` pi setup
bases/                  prebuilt base images (bench-base:*) with corporate CA patch
certs/                  corporate root CA (baked into bases)
specs/plan.json         canonical task plan (524 tasks: 76 main, 64 hard, 384 skill probes)
reference/corpus/       sampled reference tasks from Nemotron/TMax used as starting points
tools/                  make_plan.py, make_corpus.py, lint_tasks.py
jobs/                   harbor run outputs
```

## Task tiers

- `<item-id>-main` — easy/medium task covering all soft+technical skills of the item.
- `<item-id>-hard` — hard variant, created when the item's combined skill depth ≥ 8.
- `skill-<slug>` — easy/trivial probe for one technical skill (one per unique skill).

## Running

```bash
# build the three base images once (already built on this machine)
# (see bases/*.Dockerfile)

# single task, oracle check
harbor run -p tasks/golden-example -a oracle -y -o jobs

# full benchmark with the `p` pi setup + deepseek-flash, concurrency 20, 1 rollout
PYTHONPATH=$PWD/agents harbor run \
  -p tasks \
  -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 20 -k 1 -y -o jobs --job-name deepseek-flash-full
```

`p_agent:PAgent` subclasses harbor's built-in `pi` agent and adds the lean
`p` profile flags (`--no-extensions --no-skills`); the host-specific `p`
extensions (voice STT, mlx, etc.) don't apply inside eval containers.

## Notes

- Base images `bench-base:{ubuntu-24.04,python-3.12,node-22}` carry the
  corporate TLS-intercept root CA so in-container HTTPS (pip, npm, HF, GitHub)
  works. Task Dockerfiles should always build `FROM bench-base:*` (or replicate
  the CA patch).
- Reference corpora: NVIDIA Nemotron-Terminal-Synthetic-Tasks (CC-BY-4.0),
  allenai TMax-15K (ODC-BY), nebius SWE-rebench-V2 (CC-BY-4.0).

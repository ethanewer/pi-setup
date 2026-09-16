# Three-front-end validation

Result: all three tasks accepted and registered additively. Existing registration
entries and task files were preserved. See `manifest.json` and `accepted/` for
the final fingerprints, command results, measured timings, and source identities.

All task and skill authoring, including repairs, ran through Codex CLI with
`-m gpt-5.6-luna -c 'model_reasoning_effort="medium"'`. Session `turn_context`
records independently confirm those settings. Generation prompts and transcripts
are preserved in `generation/`; blind solve transcripts and solutions are in
`pilots/`. No pre-existing task files were modified.

| Pipeline | New task | New source | Oracle | Nop | Blind pilot |
| --- | --- | --- | --- | --- | --- |
| Skills | `rich-log-triage` | Rich reporting skill, authored from Textualize/rich | 1 | 0 | 1 |
| Repository | `pyyaml-config-overlay` | yaml/pyyaml | 1 | 0 | 1 |
| PR/issue | `freezegun-issue-repair` | spulec/freezegun, PR #583 | 1 | 0 | 1 |

## Sources and generation

The supplied CSV was used as a repository catalog, not as task content:
`/Users/ethanewer/posttraining-2606/local/data/terminal_docs_v004/libraries_frameworks_github.csv`.
Its SHA-256 was
`bfd194fac66fecc11bc53fab590db53f6991bb37b3187a113aabf23dd1d5da42`.
The selected rows are Rich, YAML, and freezegun. None of these repositories was
already cloned by an existing task Dockerfile when selected.

- Rich: `9d8f9a372cc5916fd4781fec207ced7ddac2f08f`, MIT. The new reusable skill is
  `authoring/skills/rich-reporting/SKILL.md`; its hash is recorded in the candidate.
  Skill validation passes. The skill is an authoring input, not an answer fixture.
- PyYAML: `34a9bf82357f4952d8f194a5a31f1c39743652d0`, MIT. The packaged upstream
  snapshot matches the checkout (excluding its local test cache and git metadata).
  The new objective is a safe recursive overlay API and command-line interface.
- Freezegun: base `c9bf52c5aa12ea1b5b8647a136a92504ea071f2f`, repair
  `8df34959e3b094f3190cb1a7191309296a1aaac8`, Apache-2.0. PR #583 supplies a real
  double-invocation regression. The baseline fails and repair passes the same
  reproduction; hidden tests separately check injection, generators, context
  managers, and ordinary decorators.

Detailed receipts are in `authoring/sources/` and normalized contracts in
`authoring/candidates/`. Each front-end normalization command ran successfully.

## Behavior, isolation, and negative controls

Independent QA found and sent these defects back to the authoring CLI:

- The first repository draft had a documentation-only hidden-case directory.
  It now executes real hidden cases; scoped lint rejects documentation-only cases.
- The YAML reference leaked DELETE markers through absent-key subtrees. Hidden
  tests now cover new nested structures, malformed placements, cycles and copy
  isolation. Previously faulty shallow-copy and unique-list variants fail.
- A blind YAML solver correctly rejected invalid input during loading, but a
  hidden test required later rejection during application. The verifier now
  permits either correct rejection stage and still tests the direct API. The
  unchanged blind solution passes the corrected verifier.
- The issue draft imposed an unstated byte-identical reproduction requirement.
  It now checks behavior, documents the source override interface, keeps pristine
  ground truth under verifier fixtures, and preserves normal API behavior.
- Rich validation, long literal output, dependency pins, and declared permissions
  were aligned across instructions, oracle, and hidden tests. C0/DEL/C1 controls,
  malformed records and I/O failures are tested.

Oracles and hidden tests are outside the agent images. Pilots received only task
instructions and fresh starting containers, with networking disabled and 1 CPU /
4096 MB. Hidden tests were copied into those containers only after the pilot CLI
had finished. All three independent solutions passed. Their transcripts and
deliverables were retained before the temporary containers were removed.

## Runtime and reproducibility

Static layout and binary-reward checks pass. All tasks declare offline networking,
CPU/memory budgets, immutable source revisions, and pinned runtime dependencies.
Image sizes measured approximately 81–85 MB (Docker image-reported bytes).

The installed Harbor 0.22.0 Docker provider rejects `network_mode="no-network"`.
The shared backend therefore has an explicit direct-Docker runtime option. It
builds the same environment, starts fresh containers with `--network none`,
enforces CPU/memory limits, mounts grader material read-only, validates both
rewards, and records image identity, elapsed time and command status. It does not
relax task networking. Earlier Harbor oracle/nop runs with the default network
policy also passed, but are not the offline acceptance evidence.

Runtime evidence before acceptance is under `qa/results/frontend-validation/`.
Acceptance repeats both controls on the same fingerprint. Release copies of
acceptance reports and logs are retained under this report's `accepted/` directory.
The estimated difficulty rubrics remain provisional: one successful blind pilot
per task proves an initial solvability check, not a statistically calibrated pass
rate or a reliable model comparison.

## Contamination and diversity

See `contamination/summary.json`, its fingerprint and full scan reports, and
`contamination-review.md`. Final gates report zero exact files, hard blocks,
text n-grams, canaries, shared source repositories, or flagged instruction pairs.
The narrowly reviewed repeated-digit primitive and two soft idiom matches are
documented with the raw pre-review report retained.

The tasks exercise different work: structured incident reporting from a skill,
new functionality inside a real parser repository, and repair of a real upstream
regression. Their objectives, source repositories, and acceptance checks differ.
No benchmark supplied an authoring objective, repository choice, solution, or
coverage target.

## Reproduce

From `evals/general`, for each candidate:

```sh
python3 tools/qa_task.py --candidate authoring/candidates/TASK.json --runtime-only --runtime-backend docker
python3 tools/qa_task.py --candidate authoring/candidates/TASK.json --review qa/reviews/TASK.json --runtime-backend docker
```

The candidate audit command is `python3 qa/audit_candidates.py`, with repeated
`--candidate` arguments, `--reference-root` pointing at the verified checkout,
and a new `--output` directory. It limits reference indexes to signatures that
can actually match the candidates, preserving match thresholds and reference
frequencies while avoiding the full suite's memory cost. Regression tests compare
retained block signatures and boilerplate decisions against the original audit.

Infrastructure verification: eight authoring/backend regression tests and three
scoped-audit tests pass. The skill validator and suite difficulty check pass.
Registration added exactly three entries and preserved all 805 existing difficulty
entries and all existing coverage records. A repeat registration skips all three.

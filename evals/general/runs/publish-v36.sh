#!/usr/bin/env bash
# Publish v3.6: the v3.5 records carried forward unchanged, with an audit bundle
# that matches the dependency-pinned tree.
#
# No record changes and no re-runs. Pinning the Python dependencies and the base
# images is a reproducibility fix: it stops a committed Dockerfile from silently
# building a different environment next month. Every task still passes its own
# reference solution under the pins, so nothing about what the tasks measure moved
# and the eighteen-hundred-odd reward files are byte-identical to v3.5.
#
# It still warrants a version, because the dataset ships audit/provenance.json,
# which hashes every task file. 209 Dockerfiles changed, so v3.5's bundle no longer
# describes the repository the records came from.
set -uo pipefail
EVAL=/home/ee/pi-setup/evals/general
set -a; . /home/ee/.env; set +a
[ -n "${HF_TOKEN:-}" ] || { echo "FATAL: HF_TOKEN not set" >&2; exit 1; }

ARGS=(--version v3.6
      --mirror /tmp/hf-upload/v3.5
      --out /tmp/hf-upload/v3.6
      --repo eewer/general-agent-bench-results
      --extra /tmp/v34_census_before.json
      --extra /tmp/v34_census_after.json
      --extra /tmp/v34_defects.json
      --extra /tmp/v34_never_passed.json
      --extra /tmp/v35_negative_control.json
      --extra /tmp/v36_dependency_pins.json
      --note "v3.6 = the v3.5 records carried forward byte for byte, with an audit bundle that matches the dependency-pinned tree. 785 tasks, six pairs, 4,710 records, every reward exactly 0 or 1. No record changed and nothing was re-run: pinning dependencies is a reproducibility fix, not a change to what any task measures. The version exists because the dataset ships audit/provenance.json, which hashes every task file, and 209 Dockerfiles changed."
      --note "Every pip requirement in every task image is now pinned. 301 requirements across 209 Dockerfiles and 89 packages previously floated, so the same committed Dockerfile built a different environment over time; numpy alone floated in 111 tasks. Versions were resolved with each base image's own interpreter against the index the task names, because the pytorch CPU index serves different builds than PyPI and the bases carry different Pythons (3.11.2 on bench-base:node-22 against 3.12.13 on bench-base:python-3.12). Recorded in specs/pinned_python_deps.json and gated by tools/pin_python_dependencies.py."
      --note "The drift was not hypothetical. amber-dial's Dockerfile carried the comment 'torch is pulled as the CPU build (default wheel on this base)' while pip resolved 2.13.0+cu130, a CUDA build, and that mismatch was load-bearing: the CUDA torch sizes its intra-op thread pool from the host core count, which produced the 325x slowdown against a one-CPU quota that made the task's own reference solution exceed the verifier's budget. A fresh build during this work resolved torch to 2.14.0, so the environment had already moved again."
      --note "The three base images were an undocumented local dependency: built from bases/*.Dockerfile, which is committed, but with floating FROM tags and present only in one machine's docker store with no RepoDigests, so a fresh clone could build none of the 785 tasks. All three FROM lines are pinned by digest and nvm's node is pinned to 22.23.2. bench-base:ubuntu-24.04 and bench-base:node-22 share every upstream layer with their pins and rebuild identically. bench-base:python-3.12 does not -- it shares ZERO layers with the current python:3.12-slim, upstream moved since 2026-09-02, and the original digest was never recorded, so rebuilding from the pin yields a different base than the one 638 tasks were validated on. That is recorded as a machine-readable rebuilds_identically field rather than left in a comment."
      --note "apt is deliberately NOT pinned: 161 packages across 209 task Dockerfiles. Debian and Ubuntu rotate their archives, so an exact version pin stops resolving once that version is published out, converting silent drift into a hard build failure across a quarter of the suite. This is observable, not theoretical -- at twelve concurrent builds twenty tasks failed with apt-get exit 100 because the mirrors throttled the simultaneous fetches, including v1-skill-telnet which installs nothing but telnet and builds fine alone. Reproducible apt needs a snapshot mirror or vendored .debs; the gap is recorded in the spec rather than pinned into breakage."
      --note "Two pinning traps were found by building, not by reasoning. Resolving each package independently with --no-deps contradicts a site's own existing pins: zephyr-bridge pins numpy==1.26.4 and gensim==4.3.3, and its bare scipy resolved alone to 1.18.1, which requires numpy>=2 and does not build; resolved as a whole site with dependencies, pip picks 1.13.1. And pinning a package that apt already provides turns a no-op into an unbuildable upgrade: arid-orchid's bare numpy and pillow were already satisfied by python3-numpy and python3-pil, so pinning them to the newest PyPI versions failed with 'Cannot uninstall numpy 1.26.4, RECORD file not found. Hint: The package was installed by debian.' Both are recorded as per-task overrides."
      --note "Validated by re-running the full oracle census over all 785 tasks against the pinned Dockerfiles: 784 passed on the first run, and the one failure was arid-orchid, fixed after that census started and passing on its own at reward 1 with all four hidden cases. Every task in the suite builds and passes its own reference solution with fully pinned Python dependencies."
      --note "Both timeout conventions remain published per pair. The leaderboard is verifier-authoritative; results.json also carries the strict variant where any agent_timeout counts 0. The choice reorders the table, so it is stated rather than left implicit."
)

echo "=== [$(date -Is)] publishing v3.6 (records unchanged from v3.5) ==="
"$EVAL/tools/publish_version.sh" "${ARGS[@]}"
rc=$?
echo "=== [$(date -Is)] publish_version.sh rc=$rc ==="
exit $rc

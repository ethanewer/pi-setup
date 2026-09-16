# bracket-quay: a self-authored 37-module Python documentation generator
# (`quaydoc`) with a real git history, a green pytest suite, one regression
# reachable only through a two-module interaction, and a postmortem deliverable.
#
# The repository is GENERATED at image-build time by environment/files/generator
# (a reproducible fixture generator: it writes the corpus under
# /app/generator/corpus/** into /app/quayside, stages 31 commits with fixed
# dates, and self-checks suite-green + hidden-red properties). Everything an
# agent needs is baked in; trials run with network_mode: none.
FROM bench-base:python-3.12

# Single-CPU task: keep any numeric pool at one thread (the suite mandates this
# for python-3.12 images even though quaydoc is pure stdlib).
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PIP_NO_CACHE_DIR=1

# pytest for the shipped suite (pinned; the only third-party package involved).
RUN pip install --no-cache-dir pytest==7.4.4

# The repository is built by the generator below, which runs `git init` /
# `git commit` in a root-owned tree; trials may run as uid 1000, so record the
# safe.directory exception system-wide, and give the build-time commits an
# identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@quayside.local" \
 && git config --system user.name "quayside build"

WORKDIR /app
COPY files/ /app/

# Build the repository fixture and prove the properties the task depends on:
#   * the shipped pytest suite is GREEN before the agent arrives,
#   * the hidden-class checks are RED on the pristine (regressed) tree and go
#     green under the canonical repair,
#   * the shape contract holds (module count, LOC, commit count, test count).
#
# The generator and its self-checks are build-time tooling only: they contain
# the canonical fix and the regression marker, so they are REMOVED from the
# image afterwards (the fixture stays reproducible from environment/files in
# the source tree, which is where the generator lives).  The trial agent must
# be able to edit files in place, so the whole tree is left writable by any
# uid (harbor trials may run as root or as uid 1000).
RUN python3 /app/generator/generate.py \
 && cd /app/quayside && python3 -m pytest -q tests \
 && python3 /app/generator/selfcheck.py \
 && rm -rf /app/generator \
 && chmod -R a+rwX /app

CMD ["/bin/bash"]
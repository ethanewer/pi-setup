# cistern-loom: a 5000+ LOC TypeScript repository (strictness migration).
#
# bench-base:node-22 ships node 22, npm and Python 3.11; the repository is
# generated at image-build time by files/gen (deterministic renderer +
# staged git history) and proven green in both directions by selfcheck.py
# before the harness ever sees it.
FROM bench-base:node-22

ENV OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# The repository is created by this build (root-owned), so record a system-
# wide safe.directory for whichever user the trial runs as, and give the
# build-time commits (and the agent's later commits) an identity.
# git refuses to operate on a repository owned by another user: it exits 128
# with "detected dubious ownership" unless the exception is recorded here.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@cistern.local" \
 && git config --system user.name "cistern build"

WORKDIR /app
COPY files/ /app/

# Build the repository with its full git history, install its (pinned)
# devDependencies offline from the build, and prove the fixture properties
# with the shipped self-check before removing the generator from the image.
RUN bash /app/gen/assemble.sh \
 && python3 /app/gen/selfcheck.py /app/cistern \
 && rm -rf /app/gen \
 && chmod -R a+rwX /app/cistern

CMD ["/bin/bash"]
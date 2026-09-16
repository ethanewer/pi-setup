# capstan-pilot: a real bug in git's built-in `git notes add` which launches
# the editor even when the note contents were fully supplied on the command
# line, whenever the supplied contents are empty (zero-length).
#
# Upstream: https://github.com/git/git (git 2.46 era). This repository is NOT
# among the frozen Terminal-Bench 2.1 reference sources (verified against
# specs/tb21_source_repositories.json; github.com/git/git absent).
#
# The deliverable tree in /app/src is checked out at the PARENT of the fix: an
# agent gets the real repository with the bug still present (the editor
# decision is made from the *accumulated buffer length* via the d.given flag).
# The fix commit itself (8b426c84...) is never made reachable from /app/src:
# only its parent is fetched there, and the golden regression test is
# extracted from the fix commit inside a throwaway clone that is deleted.
FROM bench-base:ubuntu-24.04

# Toolchain + live deps for building git 2.46 on 24.04. Everything is baked
# in; nothing is fetched at trial time (network_mode: none).
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      build-essential libssl-dev zlib1g-dev libcurl4-openssl-dev \
      libexpat1-dev gettext file unzip git \
 && rm -rf /var/lib/apt/lists/*

# Git safe-directory (repo is root-owned; trials may run as uid 1000) and a
# build-time identity for the build-time fetches.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONUNBUFFERED=1

# Deliverable clone: fetch ONLY the parent commit, depth 1, fail closed if the
# pin ever moves. The fix commit is a CHILD of this commit, so fetching this
# SHA brings neither it nor any tree it touched into /app/src.
ARG UPSTREAM_SHA=39bf06adf96da25b87c9aa7d35a32ef3683eb4a4
RUN git init /app/src && cd /app/src \
 && git remote add origin https://github.com/git/git.git \
 && git fetch --depth 1 origin 39bf06adf96da25b87c9aa7d35a32ef3683eb4a4 \
 && git checkout -q -B master FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# Golden regression test (the project's own t/t3301-notes.sh at the FIX
# commit, which adds the 'empty notes do not invoke the editor' test) from a
# throwaway clone that is then deleted, so no fix-commit bytes linger anywhere
# reachable from /app/src.
RUN mkdir -p /opt/golden && git init -q /tmp/golden-fetch \
 && git -C /tmp/golden-fetch remote add origin https://github.com/git/git.git \
 && git -C /tmp/golden-fetch fetch --depth 1 origin 8b426c84f376657e1e10839f3f5dafd9ba99593d \
 && git -C /tmp/golden-fetch show 8b426c84f376657e1e10839f3f5dafd9ba99593d:t/t3301-notes.sh \
      > /opt/golden/t3301-notes.sh \
 && chmod 644 /opt/golden/t3301-notes.sh \
 && rm -rf /tmp/golden-fetch

# Build once as a cached layer so the agent's and verifier's work is purely
# incremental. The suite pins the TRIAL container to cpus=1; the image build
# may use all available cores.
RUN cd /app/src && make -j"$(nproc)" > /tmp/git-build.log 2>&1 \
 && test -x /app/src/git \
 && /app/src/git --version

WORKDIR /app

# Authored convenience helper only (no upstream bytes in this tree).
COPY files/ /app/
RUN chmod +x /app/repro.sh && chmod -R a+rwX /app /app/src

CMD ["/bin/bash"]
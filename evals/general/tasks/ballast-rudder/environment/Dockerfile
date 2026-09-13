# ---------------------------------------------------------------------------
# ballast-rudder: mypy aborts the whole check with INTERNAL ERROR when the
# rvalue of a multiple assignment (`a, b = f(...)`) is a call to an overloaded
# function and the assignment-target context selects an overload whose return
# type is not a fixed-length tuple.
#
# The image clones python/mypy and checks out upstream PARENT commit
# 5bb72b788d5c031244f04f30f571f6fa199871ad (the commit immediately before
# upstream commit 0221c8018430c27607ff5e41d3127bd48a3e6170 fixed issue #21830),
# so the agent gets the real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself: the fix commit and all later
# history are unreachable from /app/src. The project's own regression test for
# the bug is extracted from the FIX commit at image-build time into
# /opt/golden/ (throwaway bare clone, deleted afterwards), so the fixed test
# bytes never enter the audited task tree and never remain in the working
# clone. The build-time smoke runs prove the image ships the mined failing
# state: the CLI reproduction exits 2 with INTERNAL ERROR, and the two golden
# regression cases fail when the golden data is overlaid.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=5bb72b788d5c031244f04f30f571f6fa199871ad
ARG FIX_SHA=0221c8018430c27607ff5e41d3127bd48a3e6170

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- build toolchain --------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/python/mypy.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway bare clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git, and the fix-commit bytes live only at /opt/golden/, never in
# this repository.
RUN git init --bare /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/python/mypy.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:test-data/unit/check-tuples.test \
      > /opt/golden/check-tuples.test \
 && test "$(sha256sum /opt/golden/check-tuples.test | cut -d' ' -f1)" \
      = "f3159fac0a3ba4b2915c2b63df0b7fd5772c343d78e2a113fba4a8b84c5a6adc" \
 && grep -q "[case testMultipleAssignmentWithOverloadReinferredAsHomogeneousTuple]" \
      /opt/golden/check-tuples.test \
 && grep -q "[case testMultipleAssignmentWithOverloadReinferredAsNonTuple]" \
      /opt/golden/check-tuples.test \
 && cd / && rm -rf /tmp/fixsrc && chmod a+r /opt/golden/check-tuples.test

# ---- runtime and test environment, fully pinned (the trial has no network) --
# mypy imports librt + ast-serialize at module load (mypy/nativeparse.py); the
# cp312 wheels must be present. pytest-xdist is how upstream runs its suite
# (-nauto in pyproject), and lxml/tomli are optional imports of testcheck.
# lxml 6.1.0 needs libxml2: the wheel bundles it, no apt needed.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install typing_extensions==4.15.0 mypy_extensions==1.1.0 \
            pathspec==1.1.1 librt==0.15.0 ast-serialize==0.8.0 \
            pytest==9.0.3 pytest-xdist==3.8.0 lxml==6.1.0 tomli==2.4.1

WORKDIR /app

COPY files/ /app/

# ---- build-time smoke: the image must ship the mined failing state ----------
# 1. CLI reproduction (matching the mining run): mypy must abort the whole run
#    with INTERNAL ERROR (exit 2) instead of diagnosing the assignment.
RUN cd /app/src \
 && set +e; python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py \
      > /tmp/repro.out 2>&1; rc=$?; set -e \
 && test "$rc" = "2" \
 && grep -q "INTERNAL ERROR" /tmp/repro.out \
 && grep -q "/app/repro.py" /tmp/repro.out \
 && ! grep -q "Incompatible types in assignment" /tmp/repro.out

# 2. Golden regression cases must FAIL against the buggy tree: overlay the
#    fix-commit check-tuples.test (exactly what the verifier does at trial
#    time), run the two new cases with the project's own runner, and require
#    exactly the two expected failures. Then restore the tree to pristine so
#    the shipped image carries no working-tree change.
RUN cd /app/src \
 && cp /opt/golden/check-tuples.test test-data/unit/check-tuples.test \
 && set +e; python3 -m pytest mypy/test/testcheck.py \
      -k "testMultipleAssignmentWithOverloadReinferredAsHomogeneousTuple or testMultipleAssignmentWithOverloadReinferredAsNonTuple" \
      -o addopts="" -q -p no:cacheprovider > /tmp/golden.out 2>&1; rc=$?; set -e \
 && test "$rc" = "1" \
 && grep -q "2 failed" /tmp/golden.out \
 && git checkout -q -- test-data/unit/check-tuples.test \
 && test -z "$(git status --porcelain)"

# The trial runs as uid 1000 (and some harness modes as root); mypy needs to
# import and pytest needs to write bytecode-free caches, so open the tree.
# The smoke runs above leave a root-owned /tmp/mycache behind; open it too so a
# later `--cache-dir=/tmp/mycache` cannot hit a readonly sqlite metastore under
# a non-root trial user.
RUN chmod -R a+rwX /app/src && chmod -R a+rwX /tmp/mycache

CMD ["/bin/bash"]
# tumblehome-crest: python/mypy false-positive negative-narrowing
#
# Task: the trial clone is python/mypy at the PARENT commit holding a real bug:
# a spurious "Statement is unreachable" verdict for `if x not in container`
# on ordinary containers, observable with --warn-unreachable. The upstream
# fix (which the agent must NOT be able to look up) is in mypy/checker.py; it
# is never fetched into /app/src and is asserted unreachable below.
ARG UPSTREAM_SHA_PARENT=0007c5267287ba47a3e4acc022ecb149fcf702e2
ARG UPSTREAM_SHA_FIX=b7a8bab4e5385adf2457f6644aa70a8fceab9113

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1

# A trial may run as uid 1000, so the build creates that user and hands the
# writable tree to it from the start. System-wide safe.directory keeps git
# usable for any uid.
RUN useradd -m -u 1000 -s /bin/bash trial \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository (python/mypy) at exactly the parent
# commit, with the shallowest possible history: `git init` + one depth-1 fetch
# of the pinned SHA means the object store in /app/src holds ONLY the parent
# commit. The fix commit is NEVER fetched into this clone; it is asserted
# unreachable below. The tree is created, owned by uid 1000 and snapshotted to
# /opt/prefix-mypy-src (the pristine PRE-FIX tree the verifier runs the
# agent's reproduction against) all in this ONE RUN, so no later layer
# duplicates the bytes.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && chown -R 1000:1000 /app/src \
 && cp -a /app/src /opt/prefix-mypy-src \
 && chown -R root:root /opt/prefix-mypy-src \
 && echo "pristine pre-fix tree snapshot at /opt/prefix-mypy-src"

# Runtime dependencies for running mypy from the source checkout, plus the
# project's own test runner and its dependency (mypy's pyproject pytest config
# uses `-nauto`, requiring pytest-xdist). Exact pins resolved against this
# base image's interpreter (Python 3.12.13); see difficulty.json notes.
RUN python3 -m pip install --no-cache-dir \
      typing_extensions==4.16.0 \
      mypy_extensions==1.1.0 \
      pathspec==1.1.1 \
      librt==0.15.0 \
      ast-serialize==0.11.1 \
      pytest==9.1.1 \
      pytest-xdist==3.8.0 \
      lxml==6.1.3 \
 && python3 -m pip check

# Extract the project's own regression test for this bug (the
# testNegativeNarrowingInContainer case the fix commit adds to
# test-data/unit/check-narrowing.test) into /opt/golden using a THROWAWAY
# clone that is deleted in the SAME RUN, so the fix commit never lands in
# /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && mkdir -p /opt/golden \
 && cp test-data/unit/check-narrowing.test /opt/golden/check-narrowing.test \
 && grep -q '\[case testNegativeNarrowingInContainer\]' /opt/golden/check-narrowing.test \
 && grep -q '# flags: --warn-unreachable' /opt/golden/check-narrowing.test \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden regression test extracted to /opt/golden"

# Parent-direction confirmation 1/2 in THIS image, as the trial's uid 1000:
# the exact reproduction from the issue must yield the false positive with
# the exact command the verifier will use. Fail the build closed if the bug
# does not reproduce here (dependency-version drift).
RUN mkdir -p /tmp/buildcheck \
 && printf '%s\n' \
      'from enum import Enum' \
      'class Color(Enum):' \
      '    RED = 1' \
      'def count(colors: list[Color]) -> None:' \
      '    counts: dict[Color, int] = {}' \
      '    for color in colors:' \
      '        if color not in counts:' \
      '            counts[color] = 0' \
      '        counts[color] += 1' \
      > /tmp/buildcheck/repro.py \
 && su -s /bin/bash trial -c "cd /app/src && python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/mycache /tmp/buildcheck/repro.py" > /tmp/repro-parent.log 2>&1; rc=$?; \
    tail -3 /tmp/repro-parent.log; \
    if [ $rc -eq 0 ]; then echo "REPRO DID NOT FAIL AT PARENT - failing closed"; exit 1; fi; \
    grep -q "Statement is unreachable" /tmp/repro-parent.log \
      || { echo "unreachable diagnostic not seen at parent"; exit 1; } \
 && rm -rf /tmp/buildcheck /tmp/repro-parent.log /tmp/mycache \
 && echo "parent-direction 1/2: reproduction fails at parent in this image"

# Parent-direction confirmation 2/2: the project's own regression test for
# this bug (extracted from the FIX commit above) must FAIL against the parent
# tree. The test-data file is restored to its pristine parent content right
# after, in the same RUN, so the shipped tree stays byte-identical to the
# parent commit.
RUN su -s /bin/bash trial -c "cp /opt/golden/check-narrowing.test /app/src/test-data/unit/check-narrowing.test && cd /app/src && python3 -m pytest mypy/test/testcheck.py -k testNegativeNarrowingInContainer -q -p no:cacheprovider" > /tmp/golden-parent.log 2>&1; rc=$?; \
    tail -4 /tmp/golden-parent.log; \
    if [ $rc -eq 0 ]; then echo "GOLDEN PASSED AT PARENT - failing closed"; exit 1; fi; \
    grep -q "1 failed" /tmp/golden-parent.log \
      || { echo "golden did not fail at parent"; exit 1; } \
 && cp /opt/prefix-mypy-src/test-data/unit/check-narrowing.test /app/src/test-data/unit/check-narrowing.test \
 && chown 1000:1000 /app/src/test-data/unit/check-narrowing.test \
 && rm -rf /app/src/.pytest_cache /tmp/golden-parent.log \
 && echo "parent-direction 2/2: golden regression test fails at parent in this image"

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so the fix commit
# object and every blob it introduced are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden test, of the pre-fix source file, and of
# the interpreter/toolchain the verifier executes, so the verifier can detect
# substitution by an adversarial (e.g. root) agent. /opt is made read-only for
# everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/check-narrowing.test > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix-mypy-src/mypy/checker.py > /opt/pins/prefix-checker.sha256 \
 && sha256sum /usr/local/bin/python3 /usr/local/bin/pytest /usr/bin/git /usr/bin/bash /usr/bin/su \
      > /opt/pins/toolchain.sha256 \
 && chmod -R a+rX /opt/prefix-mypy-src \
 && chmod -R a-w /opt/prefix-mypy-src \
 && chmod 555 /opt/pins /opt/golden \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/check-narrowing.test \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 5 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-checker.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + pre-fix source + toolchain pinned"

# Every writable path (the tree, its test-data, future artifacts) must be
# usable by root and by uid 1000 alike.
RUN chmod -R a+rwX /app/src

COPY files/ /app/
RUN chmod a+rwX /app \
 && chmod 644 /app/README.md

WORKDIR /app

CMD ["/bin/bash"]
# chainplate-current: mypy crashes on partial types with `--allow-redefinition`
# and a `global` declaration (upstream issue #21428).
#
# The image clones python/mypy SHALLOW at the PARENT commit 1730c953... (the
# real upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays that fixed test data into the tree exactly as the
# mining reproduction did, so
#   python3 -m pytest mypy/test/testcheck.py -k testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2 -q -o addopts=""
# fails inside the image with the mined symptom (1 failed, AssertionError
# "Unexpectedly encountered partial type"), and the CLI reproduction
# (module-level `x = []` plus a function declaring `global x`, with
# --allow-redefinition) exits 2 with an INTERNAL ERROR. The fix commit is
# fetched only into a throwaway bare clone that is deleted, so it is never
# reachable from /app/src. python/mypy is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
#
# mypy is pure Python: `python3 -m mypy` runs straight from the tree with only
# the pinned runtime deps below, and the project's own pytest suite runs
# directly from the checkout too. The verifier's "nothing else broke" gate is
# the whole mypy/test/testcheck.py data-driven suite (~8000 cases, ~4 min at
# 1 CPU); mypy's pyproject.toml adds `-nauto` to pytest's addopts, so every
# pytest invocation in the build, the oracle, the verifier and the instruction
# clears addopts (`-o addopts=""`) to avoid fanning out to one worker per CPU
# inside a one-CPU container.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=1730c9535e464be8a1eee4d74f74156d75a6c0b2
ARG FIX_SHA=3f0c355b7b5fbce50fc192a697bbe4f214e01253

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- runtime + test dependencies (pinned; the versions the pinned parent
#      checkout itself ships in test-requirements.txt) ------------------------
RUN pip3 install --no-cache-dir \
        typing_extensions==4.15.0 \
        mypy-extensions==1.1.0 \
        pathspec==1.0.0 \
        librt==0.10.0 \
        ast-serialize==0.3.0 \
        pytest==8.4.2 \
        pytest-xdist==3.8.0 \
        lxml==6.0.2

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/python/mypy.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 1730c9535e464be8a1eee4d74f74156d75a6c0b2 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/python/mypy.git \
 && git fetch --depth 1 origin 3f0c355b7b5fbce50fc192a697bbe4f214e01253 \
 && mkdir -p /opt/golden \
 && git show 3f0c355b7b5fbce50fc192a697bbe4f214e01253:test-data/unit/check-inference.test \
      > /opt/golden/check-inference.test \
 && grep -q "testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2" \
      /opt/golden/check-inference.test \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the corrected regression data into the working tree -------------
RUN cp /opt/golden/check-inference.test /app/src/test-data/unit/check-inference.test

# ---- smoke: prove the mined failing state is what the image ships ------------
# 1) the CLI reproduction exits 2 with an INTERNAL ERROR; 2) the golden test
# fails exactly as mined.
RUN printf 'x = []\n\ndef f() -> None:\n    global x\n    x\n' > /tmp/repro.py \
 && cd /app/src \
 && python3 -m mypy --no-incremental --allow-redefinition \
        --cache-dir=/tmp/mycache /tmp/repro.py > /tmp/repro.log 2>&1; \
    rc=$?; \
    test "$rc" -eq 2 \
    && grep -q "INTERNAL ERROR" /tmp/repro.log
RUN cd /app/src \
 && python3 -m pytest mypy/test/testcheck.py \
        -k testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2 \
        -q -o addopts="" > /tmp/smoke.log 2>&1; \
    grep -q "1 failed" /tmp/smoke.log \
    && grep -qF "Unexpectedly encountered partial type" /tmp/smoke.log \
    && grep -qF "testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2" /tmp/smoke.log

WORKDIR /app

# The tree is owned by the root build user; open it for whichever uid the
# trial uses (the agent must edit sources in place).
RUN chmod -R a+rwX /app/src

CMD ["/bin/bash"]
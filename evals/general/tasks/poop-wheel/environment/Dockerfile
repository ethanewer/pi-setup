# poop-wheel: semgrep/semgrep validator-rule blocking bug (upstream issue #9943).
#
# The image clones semgrep/semgrep SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ and overlays it into the working tree exactly as the mining
# reproduction did, so `pytest cli/tests/default/unit/test_rule_match.py`
# fails inside the image with the mined symptom (3 failed / 13 passed, the
# three parametrized cases of test_validator_rule_blocking). The fix commit
# is fetched only into a throwaway bare clone that is deleted afterwards, so
# the fix is never reachable from /app/src/.git (asserted at build time with
# `! git cat-file -e` and re-asserted by the verifier at trial time). A
# read-only pristine copy of the tree is kept at /opt/pristine so the
# verifier can run the agent's own reproduction against the pre-fix tree
# concept. semgrep/semgrep is not a Terminal-Bench 2.1 source repository
# (checked against specs/tb21_source_repositories.json).
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=ae531156ca6f2f692827696723e35b786fb7fa92
ARG FIX_SHA=c7d2925fbe7495bc9684f61be6212a438e438dd2

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# Fetch ONLY the pinned parent commit into a fresh git init. We deliberately do
# NOT shallow-clone the default branch first: a depth-1 clone of the default
# branch (a much newer tip) would keep that tip's blobs in the object store, and
# the develop tip already contains the FIXED rule_match.py for this issue, which
# an agent could read with zero network. With fetch-only-parent the object store
# holds exactly one commit (the parent) and no post-fix content exists anywhere
# (asserted by the log --all count below and by `git cat-file -e`).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/semgrep/semgrep.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout --detach FETCH_HEAD \
 && git submodule update --init cli/src/semgrep/semgrep_interfaces \
 && git remote remove origin \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git log --all --oneline | wc -l)" = "1" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix object never enters /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/semgrep/semgrep.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:cli/tests/default/unit/test_rule_match.py \
      > /opt/golden/test_rule_match.py \
 && test "$(sha256sum /opt/golden/test_rule_match.py | cut -d' ' -f1)" \
      = "f45c58e60aecc51d5c6d61011fdd91511fde7c3ba127492191174d3c54e30e1e" \
 && grep -q "test_validator_rule_blocking" /opt/golden/test_rule_match.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test into the tree; make the tree editable -------
# Only the paths the agent needs are made writable (the source package, the
# unit-test dir, and the repo root for the pytest cache), and the chmod lands
# in the same RUN as the overlay, so no layer duplicates the whole tree.
# Semgrep's own .gitignore already covers __pycache__/, .pytest_cache/ and
# *.egg-info/, so the tree's porcelain stays clean.
RUN cp /opt/golden/test_rule_match.py \
      /app/src/cli/tests/default/unit/test_rule_match.py \
 && test "$(sha256sum /app/src/cli/tests/default/unit/test_rule_match.py | cut -d' ' -f1)" \
      = "f45c58e60aecc51d5c6d61011fdd91511fde7c3ba127492191174d3c54e30e1e" \
 && chmod -R a+rwX /app/src/cli/src/semgrep /app/src/cli/tests \
 && chmod a+rwx /app/src

# ---- pristine reference tree (pre-fix tree concept for the verifier) ---------
# Byte-identical to what the agent starts with (parent tree + golden overlay),
# kept read-only and immutable: the verifier runs the agent's reproduce.py
# against it and requires the bug to be detected there.
RUN cp -a /app/src /opt/pristine \
 && chmod -R a-w /opt/pristine \
 && test "$(git -C /opt/pristine rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test "$(git -C /opt/pristine log --all --oneline | wc -l)" = "1" \
 && ! git -C /opt/pristine cat-file -e "${FIX_SHA}^{commit}"

# ---- install the package editable + the exact test deps ----------------------
# Pure-Python install (no OCaml build). pytest-mock and pytest-snapshot are
# imported by other tests in the same test file. pytest-freezegun must NOT be
# installed (breaks collection on python 3.12).
RUN cd /app/src \
 && python3 -m pip install --no-cache-dir -e ./cli \
                             pytest==8.1.1 \
                             pytest-mock==3.12.0 \
                             pytest-snapshot==0.9.0 \
 && cd / && python3 -c "import semgrep.rule_match; print('semgrep import OK')"

# ---- fail closed: the mined failing state must be present ---------------------
RUN cd /app/src \
 && python3 -m pytest cli/tests/default/unit/test_rule_match.py -q -p no:cacheprovider \
      > /tmp/smoke-pytest.log 2>&1; \
    grep -qF "3 failed, 13 passed" /tmp/smoke-pytest.log

WORKDIR /app

CMD ["/bin/bash"]
# trawler-grove: poetry's clone fallback passes explicit refs/heads/... and
# refs/tags/... revisions to `git checkout` unchanged, because the intended
# prefix-stripping never happens (the str.replace result is discarded and the
# prefix is misspelled "refs/head/"), so git dependencies pinned to an
# explicit ref either fail to clone or check out the wrong revision.
#
# The image clones python-poetry/poetry SHALLOW at the PARENT commit (the
# real upstream bug is present in the working tree), installs it editable
# into /opt/poetry-venv, extracts the project's own regression test for the
# bug from the FIX commit at build time into /opt/golden/ via a throwaway
# bare clone that is deleted immediately afterwards (the fix commit is NEVER
# reachable from /app/src and the golden test bytes never enter this task
# tree), and bakes a pristine pre-fix copy of the poetry package source at
# /opt/prefix/src so the verifier can run the agent's own reproduction
# against the pre-fix code and require it to FAIL. The tree the agent
# receives is 100% the parent commit: no regression test is overlaid, the
# agent must write its own failing reproduction first.
#
# poetry is not on the frozen Terminal-Bench 2.1 source-repository list and
# neither is the poetry-core git dependency; both were checked against
# specs/tb21_source_repositories.json (same pair chainplate-chartroom ships).
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

ARG UPSTREAM_SHA=b8383e3cda4e7336eb9048b1e7388b5b914a4653
ARG FIX_SHA=3f7feee6985853ee3bda6c92465273738a94b628

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ----------
# A depth-1 clone of the default branch cannot contain the parent SHA, so
# fetch the parent by SHA, detach onto it and fail closed if upstream moves
# (git may refuse a plain refspec fetch of an unadvertised sha, which is why
# the pinned sha is advertised by the depth-1 remote fetch above).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/python-poetry/poetry.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && git remote remove origin \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# ---- extract the upstream regression test from the FIX commit ------------
# Throwaway bare clone under /tmp, deleted in the same layer, so the fix
# commit never exists inside /app/src/.git. Replace the sha256 when the
# golden file is re-extracted.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/python-poetry/poetry.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/vcs/git/test_backend.py \
      > /opt/golden/test_backend.py \
 && test "$(sha256sum /opt/golden/test_backend.py | cut -d' ' -f1)" \
      = "c8cb85ea1fcd90f0cf5f72febcd008c0717ed580a6d350a54ea8f01b861ee561" \
 && grep -q "def test_clone_legacy_strips_ref_prefixes" /opt/golden/test_backend.py \
 && cd / \
 && rm -rf /tmp/fixsrc \
 && echo "golden regression test extracted (sha pinned)"

# ---- install: editable, so the trial imports the repaired tree -----------
# All versions were resolved on bench-base:python-3.12 at authoring time and
# are identical to the set shipped by the sibling poetry task
# chainplate-chartroom (same base image, same dev-dependency list). poetry is
# pinned to the poetry-core git revision the upstream project needs.
RUN python3 -m venv /opt/poetry-venv \
 && /opt/poetry-venv/bin/pip install "poetry-core @ git+https://github.com/python-poetry/poetry-core.git@b9663e42c808543377ae523611c4cfad68016f30" \
 && cd /app/src && /opt/poetry-venv/bin/pip install -e . --no-deps \
 && /opt/poetry-venv/bin/pip install build==1.6.1 "cachecontrol[filecache]==0.14.4" \
      cleo==2.1.0 dulwich==1.2.14 fastjsonschema==2.22.2 installer==1.0.1 \
      keyring==25.7.0 packaging==26.3 pkginfo==1.13 platformdirs==4.11.8 \
      pyproject-hooks==1.2.0 requests==2.34.2 requests-toolbelt==1.0.0 \
      shellingham==1.5.4 tomlkit==0.15.1 trove-classifiers==2026.6.1.19 \
      virtualenv==21.7.9 findpython==0.8.0 "pbs-installer[download,install]==2026.9.1" \
      deepdiff==9.1.0 pytest==9.1.1 pytest-mock==3.15.1 \
      "pytest-xdist[psutil]==3.8.0" responses==0.26.3 \
 && /opt/poetry-venv/bin/python -c "import poetry; print('poetry editable import OK:', poetry.__file__)"

# ---- pristine pre-fix package source, baked for the verifier ---------------
# The verifier runs the agent's own reproduction against this pre-fix copy
# and requires it to FAIL, proving the reproduction targets the real bug.
# /opt/prefix files are read-only for every uid.
RUN mkdir -p /opt/prefix \
 && cp -r /app/src/src /opt/prefix/src \
 && test "$(git hash-object /opt/prefix/src/poetry/vcs/git/backend.py)" \
      = "$(git -C /app/src rev-parse ${UPSTREAM_SHA}:src/poetry/vcs/git/backend.py)" \
 && chmod -R a+rX /opt/prefix /opt/golden \
 && echo "pristine pre-fix tree baked and verified against parent blob"

# ---- build-time smoke: the mined failing state MUST reproduce ------------
# Plant the golden (fix-commit) test file into a scratch position, run the
# project's own regression case against the PARENT tree, and require the
# exact mined failure ("2 failed, 2 passed"). Then restore the parent's own
# test_backend.py so the tree the agent receives is untouched, and require
# a clean git status. If the bug ever stops reproducing in this image, the
# image build fails loudly instead of shipping a task whose oracle cannot
# pass.
RUN cp /app/src/tests/vcs/git/test_backend.py /tmp/test_backend.parent.py \
 && cp /opt/golden/test_backend.py /app/src/tests/vcs/git/test_backend.py \
 && ( cd /app/src \
      && /opt/poetry-venv/bin/python -m pytest tests/vcs/git/test_backend.py \
           -k test_clone_legacy_strips_ref_prefixes --no-header \
           -p no:randomly -o addopts="" > /tmp/smoke-parent.log 2>&1; \
      echo $? > /tmp/smoke-rc ) \
 ; grep -q "2 failed, 2 passed" /tmp/smoke-parent.log \
 || { echo "SMOKE FAILURE: mined failing state did not reproduce (rc=$(cat /tmp/smoke-rc))"; \
      tail -20 /tmp/smoke-parent.log; exit 1; } \
 && cp /tmp/test_backend.parent.py /app/src/tests/vcs/git/test_backend.py \
 && rm -f /tmp/test_backend.parent.py /tmp/smoke-rc /tmp/smoke-parent.log \
 && test -z "$(git -C /app/src status --porcelain)" \
 && echo "smoke ok: 2 failed / 2 passed at parent; tree restored clean"

# ---- final belt: fix commit unreachable, HEAD still the pin --------------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test -z "$(git remote)" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# ---- open the tree for whichever uid the trial uses ----------------------
# The repo's .gitignore covers the .pyc/.pytest_cache run artifacts, so a
# suite run leaves no untracked files in the tree.
RUN chmod -R a+rwX /app/src

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app

CMD ["/bin/bash"]
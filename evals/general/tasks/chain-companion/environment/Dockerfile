ARG UPSTREAM_SHA_PARENT=27b8ad6cd50a484590cb9409e5d2a891ab56e16c
ARG UPSTREAM_SHA_FIX=bd49f9011d7dc8c6a36b3c4ae71f04060c9b3fb9

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Clone the REAL upstream repository at exactly the parent commit with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit is deliberately never fetched into this clone (an agent must
# not be able to look it up). The tree is made writable by uid 1000 in the
# same RUN that creates it, so no later CHOWN layer duplicates the bytes.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src

# A trial-time `pytest` run would drop a `.pytest_cache` directory at the
# repository root, which the repo's own .gitignore does not cover; the
# verifier's untracked-file scan uses git's standard exclude machinery
# (--exclude-standard), so cover it system-wide. (nltk.egg-info, created by
# the editable install below, is already ignored by the repo itself.)
RUN mkdir -p /etc/git-extra \
 && printf '.pytest_cache/\n__pycache__/\n' > /etc/git-extra/excludes \
 && git config --system core.excludesFile /etc/git-extra/excludes

# Install nltk editable (so `import nltk` loads the working tree the agent
# edits) plus the test dependencies, all pinned exactly. Measured end-to-end
# image build is ~14 s on one core: nltk is pure interpreted Python.
RUN cd /app/src \
 && pip install -e . \
 && pip install --no-cache-dir \
      numpy==2.5.3 \
      pytest==9.1.1 \
      pytest-mock==3.15.1 \
      pyyaml==6.0.3 \
      regex==2026.9.10 \
      click==8.5.0 \
      tqdm==4.70.1 \
      joblib==1.6.0 \
      defusedxml==0.7.1 \
 && python3 -c "import nltk; from nltk.tree import Tree; assert str(Tree.fromstring('(S (NP the cat) (VP sat))')) == '(S (NP the cat) (VP sat))'" \
 && python3 -m pytest -q -p no:cacheprovider nltk/test/unit/test_treetransforms.py 2>&1 | tail -1

# Extract the project's OWN regression test for this bug (the test file the
# fix commit adds; it does not exist at the pinned parent) into /opt/golden
# using a THROWAWAY clone under /tmp that is deleted immediately afterwards,
# so the fix commit never lands in /app/src and no upstream test bytes land
# in this task tree. Record a sha256 pin so the verifier can detect any
# substitution or edit.
RUN mkdir -p /opt/golden /opt/pins \
 && git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/nltk/nltk.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git show ${UPSTREAM_SHA_FIX}:nltk/test/unit/test_tree.py > /opt/golden/test_tree_golden.py \
 && test -s /opt/golden/test_tree_golden.py \
 && grep -q "def test_fromstring_escaped_bracket_leaf_and_label" /opt/golden/test_tree_golden.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && sha256sum /opt/golden/test_tree_golden.py > /opt/pins/golden.sha256 \
 && sha256sum /usr/local/bin/python3 /usr/local/bin/python3.12 /usr/bin/git > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/golden /opt/pins \
 && chmod 444 /opt/golden/test_tree_golden.py /opt/pins/golden.sha256 /opt/pins/toolchain.sha256

# Belt: prove the fix commit is not reachable from the trial clone, that
# HEAD is the pinned parent, and that the object store exposes exactly one
# commit (so `git log --all` cannot reveal anything else).
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git log --all --oneline | wc -l)" = "1"

WORKDIR /app

COPY files/ /app/

RUN chmod a+rwX /app

CMD ["/bin/bash"]
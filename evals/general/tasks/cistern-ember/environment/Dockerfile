ARG UPSTREAM_SHA_PARENT=079e8312c3ceee54066d2dc887da83867f2db68a
ARG UPSTREAM_SHA_FIX=1655128cfc0e8b598d5b3f361a3983f82098276b

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The REAL upstream jinja2 tree at exactly the parent commit (which contains
# the bug this task is about). `git init` + one depth-1 fetch of the pinned
# SHA keeps the object store minimal: it holds ONLY the parent commit, and
# the fix commit is never fetched into this clone, so an agent working in
# the tree cannot reach it. The 40-hex pin is asserted.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent checkout verified: $(git rev-parse --short HEAD)"

# Extract the project's OWN regression test for this bug (tests/test_async.py
# exactly as it exists at the fix commit) into /opt/golden, using a THROWAWAY
# shallow clone that is deleted immediately afterwards. Upstream test bytes
# therefore never land in this task tree (the tree is byte-audited) and the
# fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/pallets/jinja.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/test_async.py > /opt/golden/test_async_fix.py \
 && test -s /opt/golden/test_async_fix.py \
 && grep -q "test_basic_generate_async" /opt/golden/test_async_fix.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The project's test dependencies, pinned exactly (resolved against the base
# image's own Python 3.12 interpreter). trio is mandatory: the regression
# only surfaces through trio's async-generator finalizer. The library itself
# is imported from the checked-out tree: a .pth entry makes `import jinja2`
# resolve to /app/src/src for any interpreter, and every verifier/test run
# additionally sets PYTHONPATH=/app/src/src so nothing can shadow the tree.
RUN pip install --no-cache-dir MarkupSafe==3.0.3 pytest==7.4.3 pytest-timeout==2.4.0 trio==0.34.0 \
 && echo /app/src/src > /usr/local/lib/python3.12/site-packages/jinja2.pth \
 && python3 -c "import jinja2, trio, pytest, markupsafe; print('jinja2 from', jinja2.__file__)"

# Strip ALL git metadata: after this point the tree contains nothing but the
# parent-commit working files, and no diff or history archaeology of any kind
# is possible. Then freeze a byte-level provenance manifest of the pristine
# parent tree; the verifier re-hashes /app/src and requires that every file
# is still byte-identical except in exactly the three modules the fix
# needs to touch. `.git` itself is gone before the manifest is taken, so the
# manifest contains only the files the agent sees.
RUN rm -rf /app/src/.git \
 && cd /app/src \
 && find . -type f ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path '*/.pytest_cache/*' \
      | LC_ALL=C sort | while read -r f; do sha256sum "$f"; done > /opt/golden/manifest.sha256 \
 && test -s /opt/golden/manifest.sha256 \
 && grep -q 'CHANGES.rst' /opt/golden/manifest.sha256 \
 && wc -l < /opt/golden/manifest.sha256

# The image is built as root; the trial may run as root or as uid 1000.
RUN chmod -R a+rwX /app && chmod -R a+rwX /opt/golden

WORKDIR /app

COPY files/ /app/
RUN chmod -R a+rwX /app && echo "cistern-ember build complete"

CMD ["/bin/bash"]
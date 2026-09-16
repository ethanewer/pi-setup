ARG UPSTREAM_SHA_PARENT=1f914c5143250c1113089868f30eed67697dc40d
ARG UPSTREAM_SHA_FIX=cae50da40454a361fec84e58d4b44bedc5b6c0cd

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Install the project's test runner and the project itself (editable, so the
#   tree the agent edits is exactly what `import falcon` resolves to), pinned.
# Pure-Python package with zero runtime dependencies; no other deps needed.
RUN pip install --no-cache-dir pytest==8.3.5 \
 && pip install --no-cache-dir -e /app/src

# Belt: the editable install must point at the checked-out tree.
RUN python3 -c "import falcon, sys; assert falcon.__file__.startswith('/app/src/'), falcon.__file__; sys.stderr.write('falcon imported from %s\n' % falcon.__file__)"

# Extract the project's own regression test (tests/test_media_multipart.py
# exactly as it exists at the fix commit, i.e. the parent's file plus the
# added `test_multipart_parse_options_default_handlers_unique` regression
# test) into /opt/golden using a THROWAWAY clone that is deleted immediately
# afterwards, so upstream test bytes never land in this task tree and the fix
# commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/test_media_multipart.py > /opt/golden/test_media_multipart.py \
 && test -s /opt/golden/test_media_multipart.py \
 && grep -q "test_multipart_parse_options_default_handlers_unique" /opt/golden/test_media_multipart.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000 (user
# `ubuntu` already exists in the base image). Make the tree and /app writable
# by uid 1000 so editing, pytest cache files and /app/summary.md all work
# under either user.
WORKDIR /app/src
RUN chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true
COPY files/ /app/
RUN chmod a+rwX /app

ENV PYTHONPATH=/app/src
CMD ["/bin/bash"]
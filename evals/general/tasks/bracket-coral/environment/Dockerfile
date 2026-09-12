# bracket-coral: pallets/werkzeug — multipart uploads corrupted by boundary
# newline bytes.
#
# The image clones pallets/werkzeug SHALLOW at the PARENT commit (real upstream
# bug, issue #2761: the multipart decoder appends/drops CR/LF bytes around the
# last line break of a part when the part's closing boundary has not arrived in
# the buffer yet) and extracts the project's own regression test for the bug
# from the FIX commit at build time into /opt/golden/ (upstream bytes never
# enter this repository). The fix commit is never fetched into the working
# clone, so it is unreachable from /app/src; the golden extraction uses a
# throwaway bare clone that is deleted immediately afterwards.
#
# Werkzeug is pure Python: the editable install makes the checked-out (buggy)
# tree the code that gets imported.

FROM bench-base:python-3.12

ARG UPSTREAM_SHA=2a2e371f41aba5d83ca575e65a6409aaa7dc1097
ARG FIX_SHA=89ce5e5a4c59bc9d51d360fd5c205b344ecf06c8

# git safe.directory (the trial may run as uid 1000) + build identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: ONLY the buggy parent commit --------------------------
# A brand-new repository that fetches ONLY the parent commit by SHA. The
# default-branch tip (which contains the fixed code) is never fetched and
# neither is the fix commit, so neither is reachable from the object store.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pallets/werkzeug.git \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin \
 && git gc --prune=now --quiet \
 && git rev-parse HEAD

# ---- golden regression test, extracted from the FIX commit -----------------
# Throwaway bare clone; deleted right after the extraction, so the fix commit
# never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pallets/werkzeug.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA":tests/sansio/test_multipart.py \
      > /opt/golden/test_multipart.py \
 && test -s /opt/golden/test_multipart.py \
 && grep -q "test_decoder_data_start_with_different_newline_positions" /opt/golden/test_multipart.py \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; the trial is offline) --------
ENV PIP_NO_CACHE_DIR=1
RUN cd /app/src \
 && python3 -m pip install -e . \
 && python3 -m pip install MarkupSafe==3.0.3 pytest==9.1.1 pytest-xprocess==1.0.2 ephemeral-port-reserve==1.1.4

# Warm pass: the tree's own multipart tests pass at the parent commit (the 3
# pre-existing tests in tests/sansio/test_multipart.py). The golden test is
# NOT run here: it fails at the parent commit, by design.
RUN cd /app/src && python3 -m pytest tests/sansio/test_multipart.py -q -p no:cacheprovider

WORKDIR /app

COPY files/ /app/

# The image is built as root; the trial may run as root or uid 1000 and both
# must be able to write under /app.
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
# kedge-fairway: gallery-dl treats zero-byte HTTP responses (Content-Length: 0)
# as successful downloads -- it writes an empty file, records the download as
# completed and emits no warning, so an unhealthy source silently fills the
# archive with empty files.  Upstream bug mikf/gallery-dl#8661, fixed in
# 63b57459483134ecb5bbe85a137736eb69cdf39f.
#
# The image clones mikf/gallery-dl SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository).  The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone
# the agent works on; the extraction uses a throwaway bare clone that is
# deleted.  Pure Python, no submodules, no C build, no optional deps.
#
# The public GitHub mirror of gallery-dl omits 8 extractor modules (exhentai,
# nhentai, hitomi, hdoujin, hentaifoundry, hentaihand, hentainexus,
# schalenetwork) that the released wheel still ships and that
# gallery_dl/extractor/__init__.py still enumerates lazily.  An empty-module
# meta-path finder installed into site-packages supplies them, so the
# project's own test suite imports cleanly without touching the checkout.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=80a402f2673d0c8b5e5204be06fab706ae89e76a
ARG FIX_SHA=63b57459483134ecb5bbe85a137736eb69cdf39f

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.  The fix
# commit is never fetched into this clone, and `git cat-file -e` proves it is
# not reachable.
RUN git clone --depth 1 https://github.com/mikf/gallery-dl.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 80a402f2673d0c8b5e5204be06fab706ae89e76a \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/mikf/gallery-dl.git \
 && git fetch --depth 1 origin 63b57459483134ecb5bbe85a137736eb69cdf39f \
 && mkdir -p /opt/golden \
 && git show 63b57459483134ecb5bbe85a137736eb69cdf39f:test/test_downloader.py \
      > /opt/golden/test_downloader.py \
 && test -s /opt/golden/test_downloader.py \
 && grep -q "def test_http_empty" /opt/golden/test_downloader.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- warm every cache at build time; trial is offline ----------------------
# Editable install: the code the interpreter imports is exactly the checked-out
# source tree the agent repairs.
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir -e /app/src \
 && pip install --no-cache-dir pytest==9.1.1

WORKDIR /app

COPY files/ /app/

# the extractor-stub finder must live on the interpreter's sys.path
RUN cp /app/sitecustomize.py /usr/local/lib/python3.12/site-packages/sitecustomize.py \
 && chmod a+r /usr/local/lib/python3.12/site-packages/sitecustomize.py \
 && chmod -R a+rwX /app

CMD ["/bin/bash"]
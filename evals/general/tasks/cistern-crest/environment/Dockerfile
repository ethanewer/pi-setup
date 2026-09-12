# image clones mikf/gallery-dl SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree) and extracts the project's own regression
# tests for the bug from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository). The fix commit is a descendant
# of the parent, so it is NOT reachable from the depth-1 clone the agent works
# on; the extraction uses a throwaway bare clone that is deleted.
#
# The public GitHub mirror of gallery-dl omits 8 extractor modules (exhentai,
# nhentai, hitomi, hdoujin, hentaifoundry, hentaihand, hentainexus,
# schalenetwork) that the released wheel still ships and that
# gallery_dl/extractor/__init__.py still enumerates lazily. An empty-module
# meta-path finder installed into site-packages supplies them, so the
# project's own test suite imports cleanly without touching the checkout.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=a879e5d468e43fac9daf6bdc4726f853a9c85567
ARG FIX_SHA=12e2113a80eb4bf557dff4aba6e1775d74d8afc0

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/mikf/gallery-dl.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin a879e5d468e43fac9daf6bdc4726f853a9c85567 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/mikf/gallery-dl.git \
 && git fetch --depth 1 origin 12e2113a80eb4bf557dff4aba6e1775d74d8afc0 \
 && mkdir -p /opt/golden \
 && git show 12e2113a80eb4bf557dff4aba6e1775d74d8afc0:test/test_postprocessor.py \
      > /opt/golden/test_postprocessor.py \
 && test -s /opt/golden/test_postprocessor.py \
 && grep -q 'def test_mtime_none_dt' /opt/golden/test_postprocessor.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
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
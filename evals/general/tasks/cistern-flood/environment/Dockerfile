# cistern-flood: requests `no_proxy` matching is wrong at domain boundaries.
#
# The image checks out psf/requests at the PARENT commit (the real upstream
# bug is present in the working tree: a no_proxy hostname exempts any host
# that merely ends with it, and a dotted entry no longer matches the bare
# host). The project's own regression test for the bug is extracted from the
# FIX commit at build time into /opt/golden/ (upstream bytes never enter this
# repository).
#
# The working clone fetches ONLY the parent SHA (shallow), so neither the fix
# commit nor any newer tree is reachable from /app/src/.git -- an agent that
# wants the answer must implement it, not fetch it. The golden test is
# extracted from a throwaway bare clone that is deleted after the build.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=3816cfa1abd42dca21b9e837f26c59b246016aaf
ARG FIX_SHA=a4f9a5999bdb9bf2d6e7c8aa973b28cacb17134f

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only; fix commit unreachable ---------
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/psf/requests.git \
 && git fetch --depth 1 origin 3816cfa1abd42dca21b9e837f26c59b246016aaf \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
# tests/test_utils.py is an import-time member of the `tests` package (it uses
# `from .compat import ...`), so its one sibling module is extracted alongside
# it and an empty __init__.py makes /opt/golden/pkg a package; the verifier
# selects only the regression test from that module.
RUN git init -q --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/psf/requests.git \
 && git fetch --depth 1 origin a4f9a5999bdb9bf2d6e7c8aa973b28cacb17134f \
 && mkdir -p /opt/golden/pkg \
 && git show a4f9a5999bdb9bf2d6e7c8aa973b28cacb17134f:tests/test_utils.py \
      > /opt/golden/pkg/test_utils.py \
 && git show a4f9a5999bdb9bf2d6e7c8aa973b28cacb17134f:tests/compat.py \
      > /opt/golden/pkg/compat.py \
 && : > /opt/golden/pkg/__init__.py \
 && test -s /opt/golden/pkg/test_utils.py \
 && grep -q "def test_should_bypass_proxies_no_proxy_domain_boundary" /opt/golden/pkg/test_utils.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
# Pin everything. The bug is pure code logic, but keep the same versions the
# reproduction was measured against.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN cd /app/src \
 && python3 -m pip install -e '.[socks]' \
        'urllib3==2.7.0' \
        'certifi==2026.7.22' \
        'charset_normalizer==3.5.1' \
        'idna==3.19' \
        'PySocks==1.7.1' \
        'pytest==9.1.1'

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
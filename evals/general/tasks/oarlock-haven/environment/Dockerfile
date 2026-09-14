# ---------------------------------------------------------------------------
# oarlock-haven: pytest's monkeypatch undo bookkeeping records an entry for a
# mutation that failed, so monkeypatch.undo() re-raises the original exception
# instead of being a harmless no-op (upstream issue pytest-dev/pytest#14909).
#
# The image clones pytest-dev/pytest and checks out upstream PARENT commit
# efa117ad49ce197c5971b12310d53b73ed678d92 (immediately before upstream commit
# a88e91bacaa98b68fe80e07a138ce40994bd8797 fixed issue #14909), so the agent
# gets the real tree with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in
# /app/src's object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src. The golden regression test is
# extracted through a SEPARATE throwaway clone under /tmp that is deleted
# afterwards, so the fix bytes never land in the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=efa117ad49ce197c5971b12310d53b73ed678d92
ARG FIX_SHA=a88e91bacaa98b68fe80e07a138ce40994bd8797

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/pytest-dev/pytest.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone under /tmp, deleted afterwards: the fix commit never exists
# inside /app/src/.git. Upstream bytes also never enter this repository; the
# golden file lives only in the image at /opt/golden/.
RUN git clone -q --depth 1 https://github.com/pytest-dev/pytest.git /tmp/goldensrc \
 && git -C /tmp/goldensrc fetch -q --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/goldensrc show ${FIX_SHA}:testing/test_monkeypatch.py \
      > /opt/golden/test_monkeypatch.py \
 && test -s /opt/golden/test_monkeypatch.py \
 && test "$(sha256sum /opt/golden/test_monkeypatch.py | cut -d' ' -f1)" = \
      "c683f99dddb16fb51bad90284c14cf4ccc50fd4e8ad0c8cb94f238af191aeced" \
 && grep -q "def test_failed_delattr" /opt/golden/test_monkeypatch.py \
 && grep -q "def test_failed_setitem" /opt/golden/test_monkeypatch.py \
 && grep -q "def test_failed_delitem" /opt/golden/test_monkeypatch.py \
 && grep -q "def test_setitem_delitem_oldval_captured_before_mutation" /opt/golden/test_monkeypatch.py \
 && cd / && rm -rf /tmp/goldensrc \
 && chmod a+r /opt/golden/test_monkeypatch.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# pytest is a setuptools-scm project. In a shallow single-commit clone the scm
# fallback version (0.1.dev1+gefa...) sorts below what the `dev` extra's
# pytest-xdist>=3.5 needs (pytest>=7.0.0), which breaks a naive resolver. So
# the [dev] dependencies are installed exactly pinned, then the project itself
# is installed editable with --no-deps and a pretend scm version, so the
# installed version metadata is the real release the parent preceded (8.3.4).
# setuptools_scm writes src/_pytest/_version.py, which is gitignored, so the
# tree stays clean; we assert that below.
RUN pip install --no-cache-dir \
      iniconfig==2.3.0 packaging==26.3 pluggy==1.6.0 pygments==2.21.0 \
      argcomplete==3.7.2 attrs==26.1.0 coverage==7.16.0 hypothesis==6.168.0 \
      mock==5.2.0 numpy==2.5.3 pexpect==4.9.0 pytest-xdist==3.8.0 \
      pyyaml==6.0.3 requests==2.34.2 xmlschema==4.3.2 \
      sortedcontainers==2.4.0 ptyprocess==0.7.0 execnet==2.1.2 \
      setuptools==84.0.0 setuptools_scm==8.3.1 \
 && cd /app/src \
 && SETUPTOOLS_SCM_PRETEND_VERSION=8.3.4 pip install -e . --no-deps --no-build-isolation \
 && test -z "$(git -C /app/src status --porcelain)" \
 && chmod -R a+rwX /app/src

WORKDIR /app

COPY files/ /app/

RUN chmod a+r /app/README-scratch.txt

CMD ["/bin/bash"]
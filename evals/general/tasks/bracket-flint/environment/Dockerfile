# bracket-flint — upstream-regression task on pytest-dev/pytest (issue #719).
#
# The image contains the real pytest checkout at the PARENT commit of the fix
# for "a comma-terminated single-argument string in @pytest.mark.parametrize
# does not unpack one-element tuple values". The fix commit's own regression
# tests (two new tests in testing/python/metafunc.py) are extracted at build
# time into /opt/golden/ from an EPHEMERAL fetch that is deleted immediately
# afterwards, so the fix commit object never lands inside /app/src/.git and is
# not reachable from the checkout the agent works in (nor is any branch: only
# the parent SHA is ever fetched into /app/src, shallow and history-severed).
#
# The agent must reproduce the bug, localise it and fix it in the real source.
# The verifier runs the project's own parametrize test module, the golden
# regression tests and authored hidden cases through the project's own test
# runner. The trial has no network; everything needed is warmed at build time.
FROM bench-base:python-3.12

# git safe.directory for uid 1000, plus a build identity for any trial-side git.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- Immutable pins -------------------------------------------------------
# UPSTREAM_PARENT_SHA: the buggy revision the agent is given.
# UPSTREAM_FIX_SHA:    the upstream fix; used ONLY to extract its regression
#                      tests, never fetched into /app/src.
ARG UPSTREAM_PARENT_SHA=dde81b1948d1592b0156c2fdb79522ade6b4b857
ARG UPSTREAM_FIX_SHA=3fc824a62cd5f724ff2ae9a3aff721cee7cb4cbf

# --- The buggy checkout: fetch ONLY the parent commit ---------------------
# Shallow (--depth 1) and pinned by 40-hex SHA; the shallow file severs the
# history so the fix commit cannot be walked to even if it were known.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pytest-dev/pytest.git \
 && git fetch --depth 1 -q origin "$UPSTREAM_PARENT_SHA" \
 && git checkout --detach -q "$UPSTREAM_PARENT_SHA" \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_PARENT_SHA" \
 && test "$(git rev-list --count HEAD)" = "1"

# --- Golden regression tests (fix-era testing/python/metafunc.py), then gone
RUN git init -q /tmp/golden-extract \
 && cd /tmp/golden-extract \
 && git remote add origin https://github.com/pytest-dev/pytest.git \
 && git fetch --depth 1 -q origin "$UPSTREAM_FIX_SHA" \
 && test "$(git rev-parse "$UPSTREAM_FIX_SHA")" = "$UPSTREAM_FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$UPSTREAM_FIX_SHA":testing/python/metafunc.py > /opt/golden/metafunc.py \
 && test -s /opt/golden/metafunc.py \
 && grep -q "test_parametrize_single_arg_trailing_comma" /opt/golden/metafunc.py \
 && chmod -R a-w /opt/golden \
 && cd / \
 && rm -rf /tmp/golden-extract

# --- Belt: bug present, fix commit absent from the trial clone ------------
RUN cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_PARENT_SHA" \
 && if git cat-file -e "${UPSTREAM_FIX_SHA}^{commit}" 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && ! grep -q "has_trailing_comma" src/_pytest/mark/structures.py \
 && ! grep -q "test_parametrize_single_arg_trailing_comma" testing/python/metafunc.py

# --- Install: warm every cache at build time (the trial has no network) ----
# The clone is shallow (depth 1) and carries no tags, so setuptools-scm would
# fall back to 0.1.dev1 which trips the project's own `minversion = 2.0` check.
# Pretend the SCM version so the installed pytest reports 9.0.0.dev0, exactly
# as a full checkout of this commit would (9.0.0 was tagged after this commit).
ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
RUN cd /app/src \
 && SETUPTOOLS_SCM_PRETEND_VERSION=9.0.0.dev0 pip install --no-cache-dir -e '.[dev]' \
      "hypothesis==6.168.0" "pluggy==1.6.0" "iniconfig==2.3.0" \
      "packaging==26.3" "pygments==2.21.0" \
      "argcomplete==3.7.2" "attrs==26.1.0" "mock==5.2.0" \
      "requests==2.34.2" "setuptools==84.0.0" "xmlschema==4.3.2"

# Make the tree writable by uid 1000 (the trial may run as root or as uid 1000)
# and prove the imported package is the checked-out source.
RUN chmod -R a+rwX /app/src && (chown -R 1000:1000 /app/src 2>/dev/null || true) \
 && cd /tmp && python3 -c "import pytest; print('pytest', pytest.__version__, pytest.__file__)"

WORKDIR /app
COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]
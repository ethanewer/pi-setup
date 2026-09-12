# bracket-fathom: psycopg namedtuple row factory leaks a bare ValueError on
# duplicate column names instead of raising a psycopg DataError.
#
# The image clones psycopg/psycopg SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree, /app/src) and installs the
# psycopg and psycopg_pool subprojects from that tree as a REGULAR (non-
# editable) install. Editable must be avoided: the monorepo layout has a
# top-level `psycopg/` subproject directory, so with an editable install,
# running Python from the repo root silently imports that empty namespace
# directory instead of the installed package (psycopg.__file__ is None) and
# pytest breaks via fix_db's psycopg.Pipeline. A regular install beats the
# namespace directory on the path scan (verified upstream of this task).
#
# The project's own regression test for the bug is extracted from the FIX
# commit at build time into /opt/golden/ (upstream bytes never enter this
# repository). The fix commit is a descendant of the parent, so it is NOT
# reachable from the depth-1 clone the agent works on; the extraction uses a
# throwaway bare clone that is deleted. No PostgreSQL server is needed: the
# regression test drives the row-factory machinery directly.
#
# Duplicate column names should surface as psycopg.errors.DataError, like the
# other data-shape errors.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=7c9b6bee4ea6d7a4da5ce8e4bed9e4cba0c74012
ARG FIX_SHA=66e4b33fe271780d0bd02f15e94c66d52ed69cba

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# libpq runtime (psycopg loads it via ctypes; no server is needed)
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of the default branch cannot contain the parent SHA, so
# fetch the parent by SHA, detach onto it and fail closed if upstream moves.
RUN git clone --depth 1 https://github.com/psycopg/psycopg.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 7c9b6bee4ea6d7a4da5ce8e4bed9e4cba0c74012 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
# tests/utils.py is copied alongside the test file because the file uses a
# relative import ("from .utils import eur"); an empty __init__.py makes
# /opt/golden a package pytest can import cleanly from any cwd.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/psycopg/psycopg.git \
 && git fetch --depth 1 origin 66e4b33fe271780d0bd02f15e94c66d52ed69cba \
 && mkdir -p /opt/golden \
 && git show 66e4b33fe271780d0bd02f15e94c66d52ed69cba:tests/test_rows.py \
      > /opt/golden/test_rows.py \
 && git show 66e4b33fe271780d0bd02f15e94c66d52ed69cba:tests/utils.py \
      > /opt/golden/utils.py \
 && touch /opt/golden/__init__.py \
 && grep -q "test_make_nt_duplicate_names" /opt/golden/test_rows.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install: build toolchain + the tree itself (trial is offline) ---------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# setuptools/wheel pinned so the offline `--no-build-isolation` reinstalls
# (agent self-checks and the verifier) work with the same build backend.
RUN python3 -m pip install --no-cache-dir setuptools==84.0.0 wheel==0.48.0 \
 && python3 -m pip install --no-cache-dir typing-extensions==4.16.0 \
 && python3 -m pip install --no-cache-dir --no-build-isolation \
        /app/src/psycopg /app/src/psycopg_pool \
 && python3 -m pip install --no-cache-dir pytest==9.1.1 \
 && python3 -m pip check \
 && cd /tmp && python3 -c "import psycopg; print('psycopg', psycopg.__version__, psycopg.__file__)"

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
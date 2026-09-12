# cistern-basin: sqlalchemy SQLite DDL joins "WITHOUT ROWID" and "STRICT"
# without a comma-separator.
#
# The image clones sqlalchemy/sqlalchemy SHALLOW at the PARENT commit (the
# real upstream bug is present in the working tree) and extracts the project's
# own regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone the
# agent works on; the extraction uses a throwaway bare clone that is deleted.
#
# Pure-Python install: DISABLE_SQLALCHEMY_CEXT=1 skips the optional Cython
# extension build so no build artifacts land in the source tree.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=42ddb1fd5f1e29682bcd6ccc7b835999aafec12e
ARG FIX_SHA=48ad8c81115bd01d733fe1a4f78c8c30d7c2abbb

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 fetch of the parent SHA cannot contain its child (the fix commit);
# assert both the pinned HEAD and the absence of the fix object, fail closed.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/sqlalchemy/sqlalchemy.git \
 && git fetch --depth 1 origin 42ddb1fd5f1e29682bcd6ccc7b835999aafec12e \
 && git checkout --detach -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init -q --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/sqlalchemy/sqlalchemy.git \
 && git fetch --depth 1 origin 48ad8c81115bd01d733fe1a4f78c8c30d7c2abbb \
 && mkdir -p /opt/golden \
 && git show 48ad8c81115bd01d733fe1a4f78c8c30d7c2abbb:test/dialect/test_sqlite.py \
      > /opt/golden/test_sqlite.py \
 && test -s /opt/golden/test_sqlite.py \
 && grep -q "def test_create_table_without_rowid_strict" /opt/golden/test_sqlite.py \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DISABLE_SQLALCHEMY_CEXT=1

RUN cd /app/src \
 && pip install --no-cache-dir -e ".[asyncio]" \
        pytest==9.1.1 pytest-xdist==3.8.0 \
        greenlet==3.5.5 typing-extensions==4.16.0

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
ARG UPSTREAM_SHA_PARENT=19b58ffd057f23a5dc10fac5b949792f584e0494
ARG UPSTREAM_SHA_FIX=793cd8786373f5d1564493e35283b0d80cb67d96
ARG GOLDEN_TEST_SHA=ff4bb40e0957cc5630dce583fecdae3575b622b9

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG GOLDEN_TEST_SHA

# libpq5 per the mining entry's install recipe (pure-Python psycopg imports
# fine without it, but a real connection attempt would need it). System git
# is used by the build-time fetch / gold-extraction steps and by the tree
# checks; the codec mapping task itself is pure Python.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && useradd -m -u 1000 -s /bin/bash builder

# Clone the REAL upstream repository (psycopg/psycopg) at exactly the parent
# commit, with the shallowest possible history: `git init` + one depth-1
# fetch of the pinned SHA means the object store in /app/src holds ONLY the
# parent commit. The fix commit (which an agent must not be able to look up
# or fetch) is NEVER fetched into this clone; it is asserted unreachable at
# the end of the build. The package is then installed the way the mining
# entry's recipe does (non-editable site-packages copy of the touched tree,
# plus psycopg_pool and the pinned pytest). Ownership and permissions are
# fixed in the SAME RUN so nothing is copied twice in a later layer.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/psycopg/psycopg.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)" \
 && python3 -m pip install --no-cache-dir /app/src/psycopg /app/src/psycopg_pool pytest==9.1.1 \
 && chown -R 1000:1000 /app/src \
 && chown 1000:1000 /app \
 && chmod -R a+rwX /app/src \
 && chmod a+rwX /app \
 && echo "install ok"

# Warm, parent-direction checks as uid 1000, in THIS image: the installed
# psycopg is a non-editable copy of this exact tree, the existing test files
# are green, and the user-visible symptom reproduces (MSKANJI silently
# resolves to utf-8).
RUN cat > /tmp/warmcheck.sh <<'SH'
#!/bin/bash
set -e
cd /app/src
f=$(python3 -c 'import psycopg; print(psycopg.__file__)')
test "$f" = "/usr/local/lib/python3.12/site-packages/psycopg/__init__.py" \
  || { echo "psycopg is not imported from site-packages: $f"; exit 1; }
out=$(cd /tmp && python3 -c "from psycopg import _encodings as e; print(e.conninfo_encoding('user=foo dbname=bar client_encoding=MSKANJI'))")
test "$out" = "utf-8" || { echo "MSKANJI did not fall back to utf-8 at parent (got $out)"; exit 1; }
for t in test_encodings.py test_conninfo.py; do
  python3 -m pytest "tests/$t" -q -o cache_dir=/tmp/pyc-warm > "/tmp/warm-$t.log" 2>&1 \
    || { echo "warm $t failed"; tail -15 "/tmp/warm-$t.log"; exit 1; }
done
python3 -m pytest tests/test_sql.py -q -o cache_dir=/tmp/pyc-warm > /tmp/warm-test_sql.py.log 2>&1 \
  || { echo "warm test_sql failed"; tail -15 /tmp/warm-test_sql.py.log; exit 1; }
grep -q "17 passed" /tmp/warm-test_encodings.py.log || { echo "test_encodings not 17 passed"; exit 1; }
grep -q "43 passed" /tmp/warm-test_conninfo.py.log || { echo "test_conninfo not 43 passed"; exit 1; }
grep -q "44 passed, 80 skipped" /tmp/warm-test_sql.py.log || { echo "test_sql not 44 passed/80 skipped"; exit 1; }
rm -rf /tmp/pyc-warm
echo "warm checks ok: parent bug reproduces, existing tests green"
SH
RUN chmod 755 /tmp/warmcheck.sh \
 && su -s /bin/bash builder -c '/tmp/warmcheck.sh' \
 && rm -f /tmp/warmcheck.sh

# Bake a pristine PRE-FIX copy of the psycopg package at /opt/prefix/psycopg
# (from the untouched parent tree). The verifier runs the agent's own
# reproduction against this copy and requires it to FAIL, proving the
# symptom is real and that the reproduction targets it. Then extract the
# project's own regression test for this bug (tests/test_encodings.py as the
# upstream test commit carried it) into /opt/golden via a THROWAWAY clone
# that is deleted immediately afterwards, so the fix commit never lands in
# /app/src and no upstream test bytes enter this task tree. Finally record
# sha256 pins of every trust anchor and lock /opt down.
RUN cd /app/src \
 && mkdir -p /opt/prefix /opt/golden /opt/pins \
 && cp -a psycopg /opt/prefix/psycopg \
 &&  (cd /opt/prefix && find "$(pwd)" -type f | sort | xargs sha256sum) > /opt/pins/prefix-psycopg.sha256 \
 && rm -rf /tmp/upstream-golden-clone \
 && git init -q /tmp/upstream-golden-clone \
 && cd /tmp/upstream-golden-clone \
 && git remote add origin https://github.com/psycopg/psycopg.git \
 && git fetch --depth 1 origin ${GOLDEN_TEST_SHA} \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from the golden clone"; exit 1; \
    fi \
 && git show ${GOLDEN_TEST_SHA}:tests/test_encodings.py > /opt/golden/test_encodings.py \
 && test -s /opt/golden/test_encodings.py \
 && grep -q "client_encoding=MSKANJI" /opt/golden/test_encodings.py \
 && cd / \
 && rm -rf /tmp/upstream-golden-clone \
 && sha256sum /opt/golden/test_encodings.py > /opt/pins/golden.sha256 \
 && sha256sum /usr/local/bin/python3 /usr/local/bin/pytest /usr/local/bin/pip \
             /usr/bin/git /usr/bin/bash /usr/bin/sha256sum /usr/bin/grep \
             /usr/bin/find /usr/bin/sed /usr/bin/timeout \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/prefix /opt/golden /opt/pins \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/test_encodings.py \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-psycopg.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + pristine prefix package + toolchain pinned"

# Parent direction, confirmed in THIS image: planting the upstream regression
# test over the tree's copy must fail with EXACTLY the two discriminating
# rows (MSKANJI, mskanji) and pass the other 19; the tree is restored to a
# pristine clean state immediately afterwards.
RUN su -s /bin/bash builder -c 'set -e; cd /app/src; \
  cp /opt/golden/test_encodings.py tests/test_encodings.py; \
  python3 -m pytest tests/test_encodings.py -q -o cache_dir=/tmp/pyc-golden > /tmp/golden-parent.log 2>&1 || true; \
  tail -2 /tmp/golden-parent.log; \
  grep -q "2 failed, 19 passed" /tmp/golden-parent.log; \
  git checkout -q -- tests/test_encodings.py; \
  test -z "$(git status --porcelain)"; \
  rm -rf /tmp/pyc-golden /tmp/golden-parent.log; \
  echo "golden-at-parent verified (2 failed / 19 passed); tree restored"'

# Belt: prove the fix commit is not reachable from the trial clone and that
# the shipped tree is clean at the pinned parent commit. Also make the
# site-packages psycopg replaceable by uid 1000 (the verifier refreshes it
# from the agent's tree), and drop the tree's executability everywhere.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test -z "$(git status --porcelain)" \
 && echo "fix commit unreachable from trial clone; HEAD pinned; tree clean" \
 && chmod a+rwX /usr/local/lib/python3.12/site-packages /usr/local/bin \
 && chmod -R a+rwX /usr/local/lib/python3.12/site-packages/psycopg \
                   /usr/local/lib/python3.12/site-packages/psycopg-*.dist-info

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]
# ---------------------------------------------------------------------------
# yawl-offing: ORM UPDATE..RETURNING result-metadata corruption on compiled
# cache hits with synchronize_session="fetch" (upstream sqlalchemy issue
# #13439).
#
# The image clones sqlalchemy/sqlalchemy and checks out upstream PARENT commit
# 16177b8c73e492e5adaad8f51095f9981831da41 (immediately before upstream commit
# bd0da4263052b4571f3b16eda3552e134b9b1689 fixed #13439), so the agent gets the
# real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src (asserted below). The golden test is
# extracted from the FIX commit through a separate THROWAWAY clone that is
# deleted immediately afterwards, so the fix bytes never land in the working
# clone either, and no upstream bytes enter this task tree.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=16177b8c73e492e5adaad8f51095f9981831da41
ARG FIX_SHA=bd0da4263052b4571f3b16eda3552e134b9b1689
ARG GOLDEN_FILE=test/orm/dml/test_orm_upd_del_assorted.py
ARG GOLDEN_SHA=c6318f9a6154963a4f0f8c547779ef71983a040e0f7946522c21e4ad72c1e1bf
ARG PRISTINE_BP_SHA=cb5bd0704a90b7c798a9598fdb9b0e13aa4a792014e16001901f8309403ab02d

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
# No compiler is needed anywhere in this image: the 2.1.0b4 dev tree installs
# as pure Python and every dependency resolves to a prebuilt wheel on this
# base.
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/sqlalchemy/sqlalchemy.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && echo "parent pin ok: $(git -C /app/src rev-parse HEAD)"

# ---- install the project editable from the working clone -------------------
# The trial has no network; everything is baked in here. Pins are the versions
# the mining run verified (greenlet 3.5.5, pytest 9.1.1, pytest-xdist 3.8.0).
RUN python3 -m pip install --no-cache-dir \
      -e '/app/src[asyncio]' \
      'pytest==9.1.1' \
      'pytest-xdist==3.8.0' \
      'greenlet==3.5.5'

# ---- import resolution + pristine pre-fix copy -----------------------------
# The editable install must resolve `import sqlalchemy` to the checked-out
# tree. A byte-for-byte copy of the parent's lib/sqlalchemy then lives at
# /opt/pristine-lib: the verifier runs the agent's reproduction with
# PYTHONPATH=/opt/pristine-lib and requires it to FAIL there (proving the
# symptom is real in the pre-fix tree) while it PASSES against /app/src.
RUN python3 -c "import sqlalchemy,sys; sys.exit(0 if sqlalchemy.__file__.startswith('/app/src/lib/') else 3)" \
 && mkdir -p /opt/pristine-lib \
 && cp -r /app/src/lib/sqlalchemy /opt/pristine-lib/sqlalchemy \
 && test "$(sha256sum /opt/pristine-lib/sqlalchemy/orm/bulk_persistence.py | cut -d' ' -f1)" = "${PRISTINE_BP_SHA}" \
 && PYTHONPATH=/opt/pristine-lib python3 -c "import sqlalchemy,sys; sys.exit(0 if sqlalchemy.__file__.startswith('/opt/pristine-lib') else 3)" \
 && echo "pristine pre-fix copy ok"

# ---- golden test: the project's own regression test for this bug -----------
# Extracted from the FIX commit through a THROWAWAY clone, deleted afterwards,
# so the fix commit never enters /app/src/.git and the golden bytes never
# enter this task tree. Stored at /opt/golden for the verifier (and only the
# verifier) to plant at verify time; sha256-pinned to the bytes extracted
# here.
RUN mkdir -p /opt/golden \
 && git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/sqlalchemy/sqlalchemy.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && git -C /tmp/fixsrc show ${FIX_SHA}:${GOLDEN_FILE} \
      > /opt/golden/test_orm_upd_del_assorted.py \
 && test -s /opt/golden/test_orm_upd_del_assorted.py \
 && test "$(wc -l < /opt/golden/test_orm_upd_del_assorted.py)" = "891" \
 && grep -q "class CacheAdaptReturningOrderTest" /opt/golden/test_orm_upd_del_assorted.py \
 && grep -q "test for #13439" /opt/golden/test_orm_upd_del_assorted.py \
 && test "$(sha256sum /opt/golden/test_orm_upd_del_assorted.py | cut -d' ' -f1)" = "${GOLDEN_SHA}" \
 && cd / && rm -rf /tmp/fixsrc \
 && echo "golden test extracted and pinned"

# ---- parent-direction confirmation IN THIS IMAGE ---------------------------
# (a) the upstream regression test class, planted onto a THROWAWAY copy of the
#     golden under the tree's own test directory, must FAIL at the parent:
#     exactly its [update] variant must fail, [delete] must pass. The tree is
#     restored to pristine afterwards (the verifier plants the golden itself).
# (b) the direct reproduction (the shape the agent must author) must show the
#     cache-hit corruption through result.raw at the parent.
RUN cd /app/src \
 && cp /opt/golden/test_orm_upd_del_assorted.py test/orm/dml/test_orm_upd_del_assorted.py \
 && python3 -m pytest "test/orm/dml/test_orm_upd_del_assorted.py::CacheAdaptReturningOrderTest" \
      -q -p no:cacheprovider > /tmp/golden-parent.log 2>&1; \
   rc=$?; \
   tail -4 /tmp/golden-parent.log; \
   grep -qF "1 failed, 1 passed" /tmp/golden-parent.log \
      || { echo "GOLDEN DID NOT DISCRIMINATE AT PARENT (expected 1 failed, 1 passed)"; exit 1; } \
 && git checkout -q -- test/orm/dml/test_orm_upd_del_assorted.py \
 && test -z "$(git status --porcelain)" \
 && echo "golden discriminates at parent; tree restored clean"

RUN cd /app/src && python3 - <<'PY'
from sqlalchemy import create_engine, update, Integer
from sqlalchemy.orm import Session, DeclarativeBase, mapped_column, Mapped

engine = create_engine("sqlite://")


class Base(DeclarativeBase):
    pass


class T(Base):
    __tablename__ = "t"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    b: Mapped[int] = mapped_column(Integer)
    a: Mapped[int] = mapped_column(Integer)


Base.metadata.create_all(engine)
with engine.begin() as c:
    c.execute(T.__table__.insert(),
              [dict(id=i, a=i * 10, b=i * 100) for i in range(1, 5)])
opts = {"synchronize_session": "fetch"}
bad = False
for n, ident in enumerate((1, 2), 1):
    stmt = update(T).where(T.id == ident).values(b=999).returning(T.id, T.a, T.b)
    with Session(engine) as sess:
        raw = sess.execute(stmt, execution_options=opts).raw
        tc = T.__table__.c
        m = {}
        for col, name in ((tc.id, "id"), (tc.a, "a"), (tc.b, "b")):
            m[name] = (raw._metadata._index_for_key(col, False),
                       raw._metadata._index_for_key(name, False))
        row = raw.mappings().first()
        print("call %d: keymap%s row[tc.a]=%s row[tc.b]=%s" % (
            n, m, row[tc.a], row[tc.b]))
        if n == 2 and not (row[tc.a] == 20 and row[tc.b] == 999):
            bad = True
print("BUG REPRODUCES (call 2 wrong)" if bad else "BUG DID NOT REPRODUCE")
assert bad, "parent-direction: cache-hit corruption not observed"
PY

# ---- the project's own dml suite must be green at the parent ---------------
# The verifier requires the existing suite to pass on the agent's tree; an
# untouched tree must already be green (957+ tests, ~6 s at 1 CPU).
RUN cd /app/src && python3 -m pytest test/orm/dml -q -p no:cacheprovider \
      > /tmp/dml-parent.log 2>&1; rc=$?; \
    tail -2 /tmp/dml-parent.log; \
    if [ $rc -ne 0 ]; then echo "DML SUITE NOT GREEN AT PARENT"; exit 1; fi

# ---- provenance belt + permissions -----------------------------------------
RUN cd /app/src \
 && if git cat-file -e ${FIX_SHA}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git rev-list --all --count)" = "1" \
 && test -z "$(git status --porcelain)" \
 && echo "fix commit unreachable from trial clone; tree clean at $(git rev-parse HEAD)" \
 && chmod -R a+rwX /app/src /app \
 && chmod 555 /opt/golden /opt/pristine-lib \
 && chmod 444 /opt/golden/test_orm_upd_del_assorted.py \
 && chmod -R a+rX /opt/pristine-lib \
 && echo "permissions set"

COPY files/ /app/

WORKDIR /app

CMD ["/bin/bash"]
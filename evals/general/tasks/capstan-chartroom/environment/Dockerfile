# ---------------------------------------------------------------------------
# capstan-chartroom: statsmodels describe() raises on a zero-row (empty)
# DataFrame instead of returning a NaN/zero summary (upstream issue #9891).
#
# The image clones statsmodels/statsmodels and checks out upstream PARENT
# commit 52f10d214d4dc02e9b521b9f9a83c5e3d4880f94 (the commit immediately
# before upstream commit e30aa8337deebbb902d886b291ab206c3ce4e639 fixed it),
# so the agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>`, detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test is extracted
# from the fix commit into /opt/golden via a throwaway clone that is deleted,
# so the fix bytes never land in the working clone either.
#
# The fix commit's test_descriptivestats.py (parent module + the new
# parametrized `test_empty_rows`) is overlaid into the working tree, exactly
# as the mining reproduction did. Running the module's tests then shows
# test_empty_rows failing for numeric (ValueError: Length of values (2) does
# not match length of index (1)), categorical (KeyError: 2) and mixed input
# while the other 15 tests of the module pass.
#
# statsmodels is then built and installed NON-editable from the parent tree
# with a persistent meson build dir (/opt/sm-build); the built library (with
# the bug) lands in site-packages. A later incremental reinstall after the
# agent edits a pure-Python source file takes ~6 seconds at 1 CPU because
# ninja rebuilds from the warmed build dir. The source tree itself is never
# importable (the generated statsmodels/_version.py lives only in the
# installed build), which the instruction tells the agent to expect.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=52f10d214d4dc02e9b521b9f9a83c5e3d4880f94
ARG FIX_SHA=e30aa8337deebbb902d886b291ab206c3ce4e639

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- compilers + git --------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc g++ git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# [environment] declares cpus = 1: pin numeric thread pools to the budget.
ENV OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# ---- pinned runtime/ test/ build dependencies (resolved for py3.12.13) ------
RUN pip install --no-cache-dir --disable-pip-version-check \
      numpy==2.5.3 scipy==1.18.1 pandas==3.0.5 patsy==1.0.3 formulaic==1.2.2 \
      packaging==26.3 pytest==9.1.1 meson-python==0.21.1 meson==1.12.0 \
      ninja==1.13.2 cython==3.3.0 setuptools_scm==9.2.2

# ---- working clone: buggy parent commit only, fix commit unreachable --------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/statsmodels/statsmodels.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes never enter this repository either; the golden
# files live only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/statsmodels/statsmodels.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:statsmodels/stats/tests/test_descriptivestats.py \
      > /opt/golden/test_descriptivestats.py \
 && test -s /opt/golden/test_descriptivestats.py \
 && grep -q "def test_empty_rows" /opt/golden/test_descriptivestats.py \
 && grep -q "GH#9891" /opt/golden/test_descriptivestats.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the fix-commit test module onto the working tree ---------------
# Exactly the state the mining reproduction used: parent tree + the fix
# commit's test file. The file shows as modified in git status (expected).
RUN cp /opt/golden/test_descriptivestats.py /app/src/statsmodels/stats/tests/test_descriptivestats.py

# ---- build + install the buggy parent library (non-editable) ----------------
# Persistent build dir /opt/sm-build: the trial's reinstall from a repaired
# tree is then an incremental ninja step (~6s at 1 CPU) instead of a full
# rebuild. The source tree is intentionally not importable afterwards
# (generated statsmodels/_version.py lives in the installed package only).
RUN cd /app/src \
 && pip install --no-build-isolation --no-deps --no-cache-dir \
      --disable-pip-version-check --config-settings=builddir=/opt/sm-build . \
 && cd /tmp && python3 -c \
      "import statsmodels; print('installed', statsmodels.__version__, statsmodels.__file__)"

# ---- smoke: the mined failure modes must reproduce at the parent ------------
RUN cd /tmp && python3 - <<'EOF'
import pandas as pd
from statsmodels.stats.descriptivestats import describe

df = pd.DataFrame({"a": pd.Series([], dtype="float64")})
try:
    describe(df)
    raise SystemExit("BUG: numeric 0-row input did NOT raise at parent")
except ValueError as e:
    assert "Length of values (2) does not match length of index (1)" in str(e)
    print("parent numeric: ValueError as mined")
except Exception as e:  # pragma: no cover
    raise SystemExit("parent numeric raised %r, not ValueError" % (e,))

dfc = pd.DataFrame({"a": pd.Series([], dtype="category")})
try:
    describe(dfc)
    raise SystemExit("BUG: categorical 0-row input did NOT raise at parent")
except KeyError as e:
    print("parent categorical: KeyError as mined")
except Exception as e:  # pragma: no cover
    raise SystemExit("parent categorical raised %r, not KeyError" % (e,))
print("smoke: parent reproduces both mined failure modes")
EOF

# ---- smoke: the golden regression test must fail at the parent ---------------
RUN mkdir -p /tmp/paren && cp /opt/golden/test_descriptivestats.py /tmp/paren/ \
 && cd /tmp/paren \
 && python3 -m pytest test_descriptivestats.py -q > /tmp/paren-golden.log 2>&1 || true; \
    grep -q "test_empty_rows" /tmp/paren-golden.log \
 && grep -q "failed" /tmp/paren-golden.log \
 && echo "smoke: golden test_empty_rows fails at parent" \
 || { echo "SMOKE FAIL: golden test did not fail at parent"; cat /tmp/paren-golden.log; exit 1; }

WORKDIR /app

CMD ["/bin/bash"]
# ---------------------------------------------------------------------------
# chainplate-inlet: MixedLM's summary report ignores the title argument
# (upstream issue #9805).
#
# The image clones statsmodels/statsmodels and checks out upstream PARENT
# commit 3c102982fecc91782d7836b9ae456fe869dd3578 (the commit immediately
# before upstream commit 0a347973915a2a28ec795cb670343c37ab3d0d92 fixed it),
# so the agent gets the real repository with the real bug still in it.
# MixedLMResults.summary() documents "title : str, optional -- If not None,
# then this replaces the default title" but calls
# smry.add_title("Mixed Linear Model Regression Results") unconditionally, so
# every caller's title is silently ignored and the default heading is printed.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>`, detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test is extracted
# from the fix commit into /opt/golden via a throwaway clone that is deleted
# afterwards, so the fix bytes never land in the working clone either.
#
# The fix-bytes scratch dir /opt/fixcheck is removed again at the end of the
# build, after the both-directions self-confirmation: the exact upstream fix
# module must not be readable inside the trial image or the task collapses to
# a single `cp`. The golden test stays in /opt/golden for the verifier (an
# agent that edits it is still caught by the -S isolated test invocations and
# the inline reproduction).
#
# The golden test module (the fix commit's full statsmodels/regression/tests/
# test_lme.py) is run STANDALONE: the module uses one relative import
# (`from .results import lme_r_results`) and loads CSV fixtures from a
# `results/` directory next to it, so /opt/golden carries an __init__.py
# package marker and a copy of the project's own `results` package (taken
# from the pinned parent tree, where it is byte-identical) as its first
# import parent. pytest then imports the module as `golden.test_lme` with
# `golden.results` resolving beside it, while `import statsmodels` resolves
# to the installed package. No upstream bytes are modified.
#
# statsmodels is then built and installed NON-editable from the parent tree
# with a persistent meson build dir (/opt/sm-build); the built library (with
# the bug) lands in site-packages. A later incremental reinstall after the
# agent edits a pure-Python source file takes ~6-10 seconds at 1 CPU because
# ninja rebuilds from the warmed build dir. The source tree itself is never
# importable (the generated statsmodels/_version.py lives only in the
# installed build), which the instruction tells the agent to expect.
#
# Both directions are re-confirmed INSIDE this image at build time (evidence
# captured in /opt/fixcheck/):
#   parent: /app/probe_title.py reports the returned title differs from the
#           requested one (exit 1 = bug present), and the golden module run
#           fails exactly one test, test_summary_title;
#   fix:    the installed mixed_linear_model.py module is swapped for the
#           fix commit's own bytes from /opt/fixcheck/, the full golden
#           module goes green (0 failures), and the installed file is then
#           restored byte-identically (sha256 compared).
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=3c102982fecc91782d7836b9ae456fe869dd3578
ARG FIX_SHA=0a347973915a2a28ec795cb670343c37ab3d0d92

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
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && git -C /app/src status --porcelain | grep -q . && exit 1 || true

# ---- extract the upstream regression test + the fix-bytes from the FIX
#      commit (throwaway clone, deleted: the fix commit never exists inside
#      /app/src/.git and upstream bytes never enter this task's repository;
#      they live only in the image at /opt/golden and /opt/fixcheck) --------
RUN git clone --depth 1 --no-checkout https://github.com/statsmodels/statsmodels.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden/results /opt/fixcheck \
 && git show ${FIX_SHA}:statsmodels/regression/tests/test_lme.py \
      > /opt/golden/test_lme.py \
 && test -s /opt/golden/test_lme.py \
 && grep -q "def test_summary_title" /opt/golden/test_lme.py \
 && git show ${FIX_SHA}:statsmodels/regression/mixed_linear_model.py \
      > /opt/fixcheck/mixed_linear_model_fix.py \
 && test -s /opt/fixcheck/mixed_linear_model_fix.py \
 && grep -q "if title is None:" /opt/fixcheck/mixed_linear_model_fix.py \
 && touch /opt/golden/__init__.py \
 && cp -a /app/src/statsmodels/regression/tests/results/. /opt/golden/results/ \
 && test -f /opt/golden/results/__init__.py \
 && test -f /opt/golden/results/lme_r_results.py \
 && test -f /opt/golden/results/lme00.csv \
 && cd / && rm -rf /tmp/fixsrc

# ---- the agent-side reproducer script ----------------------------------------
WORKDIR /app
COPY files/ /app/
RUN chmod +x /app/probe_title.py

# ---- build + install the buggy parent library (non-editable) ----------------
# Persistent build dir /opt/sm-build: the trial's reinstall from a repaired
# tree is then an incremental ninja step (~6-10s at 1 CPU) instead of a full
# rebuild. The source tree is intentionally not importable afterwards
# (generated statsmodels/_version.py lives in the installed package only).
RUN cd /app/src \
 && pip install --no-build-isolation --no-deps --no-cache-dir \
      --disable-pip-version-check --config-settings=builddir=/opt/sm-build . \
 && cd /tmp && python3 -c \
      "import statsmodels; print('installed', statsmodels.__version__, statsmodels.__file__)" \
 && git -C /app/src status --porcelain | grep -q . && { echo 'TREE-DIRTY-AFTER-INSTALL'; git -C /app/src status --porcelain; exit 1; } || true

# ---- re-confirm direction 1 (PARENT): probe shows the title is ignored ------
RUN set +e; python3 /app/probe_title.py > /opt/fixcheck/parent-probe.txt 2>&1; rc=$?; set -e; \
    echo "parent probe exit = $rc (1 expected: title ignored)" >> /opt/fixcheck/parent-probe.txt; \
    test "$rc" = "1" \
    && grep -q "Mixed Linear Model Regression Results" /opt/fixcheck/parent-probe.txt

# ---- re-confirm direction 1 (PARENT): golden module fails exactly the -------
#      upstream regression test -- it runs twice, once for TestMixedLMSummary
#      and once for its subclass TestMixedLMSummaryRegularized which inherits
#      every test of the base class -- and nothing else
RUN ( cd /tmp && python3 -m pytest -q -p no:cacheprovider /opt/golden/test_lme.py \
        > /opt/fixcheck/parent-golden.log 2>&1 ); rc=$?; set -e; \
    echo "parent golden module exit = $rc (1 expected: test_summary_title fails in both classes)" >> /opt/fixcheck/parent-golden.log; \
    tail -25 /opt/fixcheck/parent-golden.log; \
    test "$rc" = "1" \
    && test "$(grep -cE 'FAILED ' /opt/fixcheck/parent-golden.log)" = "2" \
    && test "$(grep -cE 'FAILED .*test_summary_title' /opt/fixcheck/parent-golden.log)" = "2"

# ---- re-confirm direction 2 (FIX): swap installed module for the fix ---------
#      commit's bytes, whole golden module green, restore byte-identically
RUN python3 - <<'EOF'
import hashlib
import pathlib
import subprocess
import sys

import statsmodels.regression.mixed_linear_model as m

inst = pathlib.Path(m.__file__)
orig = inst.read_bytes()
fixed = pathlib.Path("/opt/fixcheck/mixed_linear_model_fix.py").read_bytes()
assert hashlib.sha256(orig).hexdigest() != hashlib.sha256(fixed).hexdigest(), \
    "installed module is already the fix; expected the buggy parent"

inst.write_bytes(fixed)
r = subprocess.run(
    [sys.executable, "-m", "pytest", "-v", "-p", "no:cacheprovider",
     "/opt/golden/test_lme.py"],
    cwd="/tmp", capture_output=True, text=True,
)
inst.write_bytes(orig)
assert inst.read_bytes() == orig, "installed module was not restored byte-identically"
with open("/opt/fixcheck/fix-golden.log", "w") as f:
    f.write(r.stdout)
    f.write(r.stderr)
if r.returncode != 0:
    print(r.stdout[-6000:])
    print(r.stderr[-2000:])
    raise SystemExit("fix direction FAILED: golden module not green with fix bytes")
if "test_lme.py::TestMixedLMSummary::test_summary_title PASSED" not in r.stdout:
    raise SystemExit("fix direction FAILED: test_summary_title did not run/pass")
print("fix direction OK: full golden test_lme.py green with the fix module; installed copy restored")
EOF

# ---- from here on the trial must behave exactly as it will offline ----------
# ---- the answer bytes must not survive into the trial image ----------------
# The fix module extracted above is the exact upstream fix; an agent that
# finds /opt/fixcheck needs only `cp` to complete the task. Remove it after
# the both-directions confirmation. (The fix-direction RUN step above has
# re-installed and restored the buggy module already.)
RUN rm -rf /opt/fixcheck && test ! -e /opt/fixcheck

# ---- from here on the trial must behave exactly as it will offline ----------
RUN chmod -R a+rwX /app /opt/golden /opt/sm-build

WORKDIR /app

CMD ["/bin/bash"]
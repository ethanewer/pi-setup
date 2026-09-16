# swivel-longshore — networkx group betweenness centrality bug fix
# (upstream networkx/networkx issue #8879, fix commit 73cb92bb).
#
# The image clones the REAL upstream repository at the PARENT commit
# (a7d049b4), installs it editable, bakes a pristine pre-fix copy at a
# PER-BUILD RANDOMIZED root-only path (its location is recorded in
# /opt/prefix-path, readable only by the verifier/oracle, never disclosed to
# the agent), and extracts the project's own regression tests from the FIX
# commit into /opt/golden via a throwaway clone that is deleted
# immediately. The fix commit object never enters /app/src (asserted).

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=a7d049b4992a1f7e9bd376ce7378d3825d0cfa0e
ARG UPSTREAM_SHA_FIX=73cb92bbaed12828848f2609340442119e7e0fe8
ARG P_TEST=9.1.1
ARG P_COV=7.1.0
ARG P_XDIST=3.8.0
ARG P_NUMPY=2.5.3
ARG P_PANDAS=3.0.5

# --- 1) clone the REAL upstream tree pinned to the parent commit ------------
# git init + one depth-1 fetch of the pinned SHA keeps the object store in
# /app/src to exactly ONE commit (the parent). Fail closed if the pin moves.
# Also create the uid-1000 user the trial may run as (bench-base python image
# has no unprivileged user).
RUN useradd -m -u 1000 -s /bin/bash tester \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# --- 2) editable install + pinned test dependencies + pre-fix copy ----------
# networkx 3.7rc0.dev0 is pure python; test_group.py's TestProminentGroup
# class importorskips numpy and pandas, and in pytest 9 a class-body skip
# aborts collection of the whole module, so numpy and pandas are installed
# (pinned). The pre-fix copy (a per-build random /opt/pre-* directory)
# is the pristine parent tree (no .git) used by the verifier as the
# "pre-fix tree concept" to prove the agent's reproduction detects the
# bug. Its path is kept root-only and is unknown to the agent, so a
# reproduction cannot hardcode or special-case it. Ownership of /app/src
# moves to uid 1000 in the SAME RUN that creates the files (no duplicate
# layer).
RUN cd /app/src \
 && pip install --no-cache-dir -e . \
 && pip install --no-cache-dir \
      "pytest==${P_TEST}" "pytest-cov==${P_COV}" "pytest-xdist==${P_XDIST}" \
      "numpy==${P_NUMPY}" "pandas==${P_PANDAS}" \
 && python3 -c "import numpy, pandas; print('numpy', numpy.__version__, 'pandas', pandas.__version__)" \
 && PREFIX_DIR="/root/.pre-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" \
 && cp -a /app/src "$PREFIX_DIR" \
 && rm -rf "$PREFIX_DIR/.git" \
 && chmod -R a-rwx,u+rwX "$PREFIX_DIR" \
 && echo "$PREFIX_DIR" > /opt/prefix-path \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && test -s /opt/prefix-path \
 && git status --porcelain --untracked-files=no | grep -q . \
      && { echo "tree has tracked modifications after install"; exit 1; } || true

# --- 3) extract the project's OWN regression tests from the FIX commit ------
# through a SEPARATE throwaway clone under /tmp, deleted immediately, so the
# fix commit never reaches /app/src and no upstream test bytes enter this
# task tree. The extracted file (fix-commit test_group.py) is sha256-pinned
# in step 5.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/networkx/networkx.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:networkx/algorithms/centrality/tests/test_group.py \
      > /opt/golden/test_group.py \
 && test -s /opt/golden/test_group.py \
 && grep -q "test_group_betweenness_no_paths_through_group" /opt/golden/test_group.py \
 && grep -q "test_group_betweenness_many_groups" /opt/golden/test_group.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden test extracted from fix commit; throwaway clone removed"

# --- 4) parent-direction confirmations INSIDE this exact image --------------
# (a) the direct reproduction fails at parent (buggy value 0.125);
# (b) golden tests planted over the parent tree: exactly the one upstream
#     regression test fails, the other 25 pass; then restore the tree's own
#     test file from the parent commit so the shipped tree is pristine.
RUN cat > /tmp/reprocheck.py <<'PY'
import networkx as nx
G = nx.Graph([(0, 1), (0, 2), (0, 3), (0, 4), (1, 3), (2, 3), (3, 4), (4, 5)])
v = nx.group_betweenness_centrality(G, [0, 1, 2], normalized=False)
print("gbc =", v)
assert v == 0.125, v
PY
RUN cd /app/src && python3 /tmp/reprocheck.py && rm -f /tmp/reprocheck.py \
 && cp networkx/algorithms/centrality/tests/test_group.py /tmp/pristine_test_group.py \
 && cp /opt/golden/test_group.py networkx/algorithms/centrality/tests/test_group.py \
 && python3 -m pytest networkx/algorithms/centrality/tests/test_group.py \
      -p no:cacheprovider -q > /tmp/golden_at_parent.log 2>&1; rc=$?; \
    echo "golden-at-parent rc=$rc"; cat /tmp/golden_at_parent.log; \
    if [ "$rc" -ne 1 ]; then echo "expected exactly 1 failure"; exit 1; fi; \
    grep -q "1 failed, 25 passed" /tmp/golden_at_parent.log \
      || { echo "unexpected pass/fail split at parent"; exit 1; }; \
    grep -q "0.125" /tmp/golden_at_parent.log \
      || { echo "failure value not the buggy 0.125"; exit 1; }; \
    cp /tmp/pristine_test_group.py networkx/algorithms/centrality/tests/test_group.py \
 && rm -f /tmp/pristine_test_group.py /tmp/golden_at_parent.log \
 && git status --porcelain --untracked-files=no | grep -q . \
      && { echo "tree dirty after parent-direction checks"; exit 1; } || true \
 && echo "parent direction confirmed inside this image; tree restored pristine"

# --- 5) integrity pins ------------------------------------------------------
# sha256 of the golden test, of the pre-fix group.py, and of the core
# toolchain the verifier executes, so a trial that runs as root cannot
# substitute any of them without the verifier noticing.
RUN python3 - <<'PY'
import hashlib, os
def h(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()
os.makedirs("/opt/pins", exist_ok=True)
pins = {}
with open("/opt/prefix-path") as _f:
    _PRE = _f.read().strip()
pins["golden.sha256"] = "/opt/golden/test_group.py"
pins["prefix-group.py.sha256"] = f"{_PRE}/networkx/algorithms/centrality/group.py"
pins["python3.sha256"] = "/usr/local/bin/python3"
pins["bash.sha256"] = "/usr/bin/bash"
pins["git.sha256"] = "/usr/bin/git"
pins["cp.sha256"] = "/usr/bin/cp"
pins["grep.sha256"] = "/usr/bin/grep"
for name, path in pins.items():
    if not os.path.exists(path):
        raise SystemExit(f"missing tool path: {path}")
    with open(f"/opt/pins/{name}", "w") as f:
        f.write(f"{h(path)}  {path}\n")
PY
# /opt/golden (the upstream regression tests, the withheld reproduction) and
# /opt/pins are root-only: the agent runs as uid 1000 and must not be able to
# read the regression graphs/expectations or substitute any pinned file. The
# verifier runs as root and re-verifies every pin before use.
RUN PRE=$(cat /opt/prefix-path) \
 && chmod 700 /opt/pins /opt/golden "$PRE" /opt/prefix-path \
 && chmod 600 /opt/pins/*.sha256 /opt/golden/test_group.py \
 && test -r "$PRE/networkx/algorithms/centrality/group.py" \
 && ls /opt/pins \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-group.py.sha256 >/dev/null \
 && echo "golden + pre-fix tree + toolchain pinned"

# --- 6) belt: the fix commit is NOT reachable from the trial clone ----------
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit object reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-list --count HEAD)" = "1" \
 && git diff --quiet HEAD \
 && test -z "$(git status --porcelain --untracked-files=no)" \
 && echo "fix commit object absent from /app/src; object store holds only the parent; tree clean"

# --- 7) single-CPU comfort + user-site lockdown ---------------------------
# PYTHONNOUSERSITE=1 makes EVERY python3 launched in the trial container (agent
# dev shells and verifier runs alike) ignore ~/.local user site-packages, so an
# agent-planted sitecustomize.py in its own HOME cannot silently wrap/replace
# the library under test. The verifier additionally passes -s on every python3
# invocation so this holds even if the container ENV were stripped.
ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    PYTHONNOUSERSITE=1

COPY files/ /app/
RUN chown -R 1000:1000 /app && chmod a+rwX /app && chmod a+r /app/README.md

WORKDIR /app
CMD ["/bin/bash"]
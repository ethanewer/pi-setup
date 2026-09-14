# ---------------------------------------------------------------------------
# caulk-ebb: networkx's geometric_soft_configuration_graph computes the mean
# hidden degree from a kappas MAPPING by summing the mapping's KEYS instead of
# its values. With string node labels the call raises TypeError; with integer
# node labels it silently treats the ids as the degrees (wrong density, wrong
# radial layout). Fix commit e9eac8a7e04df0b9cdcff8ed1682b3971678f4ed upstream
# (issue #8726): 'sum(kappas)' -> 'sum(kappas.values())'.
#
# The image clones networkx/networkx and checks out upstream PARENT commit
# 195092869192b762fa553ef3a9ca5758e1d83ee3 (immediately before the fix), so
# the agent gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. See the golden-test extraction below,
# which uses a throwaway clone that is deleted, so the fix bytes never land in
# the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=195092869192b762fa553ef3a9ca5758e1d83ee3
ARG FIX_SHA=e9eac8a7e04df0b9cdcff8ed1682b3971678f4ed

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable --------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/networkx/networkx.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/networkx/networkx.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:networkx/generators/tests/test_geometric.py \
      > /opt/golden/test_geometric.py \
 && test -s /opt/golden/test_geometric.py \
 && grep -q "test_S1_kappas_mean_degree_from_values" /opt/golden/test_geometric.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_geometric.py

# ---- runtime and test environment, fully pinned (trial must need no net) ----
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# networkx at this commit has no non-optional dependencies; the edit install
# needs an up-to-date setuptools/wheel.  Test deps mirror the entry recipe
# (networkx/requirements/test.txt), pinned to exact versions.
RUN pip install setuptools==84.0.0 wheel==0.48.0 \
 && cd /app/src \
 && pip install -e . --no-build-isolation \
 && pip install pytest==8.4.2 pytest-cov==6.3.0 pytest-xdist==3.8.0

# ---- site-packages manifest: the verifier rejects ANY drift from this -------
# ---- snapshot (catches interpreter hooks such as a planted           -------
# ---- sitecustomize.py or .pth shim, or a reinstall of networkx)      -------
RUN python3 - <<'PYEOF'
import hashlib, pathlib, site
root = pathlib.Path(site.getsitepackages()[0])
lines = []
for p in sorted(root.rglob("*"), key=str):
    if p.is_file() and "__pycache__" not in p.parts:
        lines.append(hashlib.sha256(p.read_bytes()).hexdigest() + "  " + str(p.relative_to(root)))
pathlib.Path("/opt/site_packages_manifest.txt").write_text("\n".join(lines) + "\n")
print("site-packages manifest: {} files".format(len(lines)))
PYEOF

WORKDIR /app

CMD ["/bin/bash"]
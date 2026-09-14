# ---------------------------------------------------------------------------
# companion-berm: stale progress-indicator label after a resolver error in
# python-poetry/poetry.
#
# The image clones python-poetry/poetry and checks out upstream PARENT commit
# 35eb5025dc7374db74ef26ce32a0e70f54d2e3b6 (immediately before upstream commit
# b8383e3cda4e7336eb9048b1e7388b5b914a4653 fixed issue #10805), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. See the golden-test extraction below,
# which uses a throwaway clone that is deleted, so the fix bytes never land in
# the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=35eb5025dc7374db74ef26ce32a0e70f54d2e3b6
ARG FIX_SHA=b8383e3cda4e7336eb9048b1e7388b5b914a4653

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/python-poetry/poetry.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# test lives only in the image at /opt/golden/. The body of the regression
# function is pulled verbatim out of the fix commit's test file with ast, so it
# is the upstream test, not a paraphrase.
RUN git clone --depth 1 --no-checkout https://github.com/python-poetry/poetry.git /tmp/fixsrc \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && git -C /tmp/fixsrc show FETCH_HEAD:tests/puzzle/test_provider.py > /tmp/fix_test_provider.py \
 && mkdir -p /opt/golden

RUN python3 - <<'PYEOF'
import ast
src = open('/tmp/fix_test_provider.py').read()
tree = ast.parse(src)
found = False
for n in tree.body:
    if isinstance(n, ast.FunctionDef) and n.name == 'test_indicator_context_resets_on_exception':
        fn = ast.get_source_segment(src, n)
        out = "import pytest\n\nfrom poetry.puzzle.provider import Indicator\n\n\n" + fn + "\n"
        with open('/opt/golden/test_indicator_context_resets_on_exception.py', 'w') as f:
            f.write(out)
        print('extracted', len(fn), 'chars from fix-commit test_provider.py')
        found = True
        break
if not found:
    raise SystemExit('regression test function not found in fix-commit tree')
PYEOF

RUN test -s /opt/golden/test_indicator_context_resets_on_exception.py \
 && grep -q "test_indicator_context_resets_on_exception" /opt/golden/test_indicator_context_resets_on_exception.py \
 && grep -q "raise RuntimeError" /opt/golden/test_indicator_context_resets_on_exception.py \
 && rm -rf /tmp/fixsrc /tmp/fix_test_provider.py

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---- runtime and test environment, fully pinned (the trial has no network) --
# poetry-core is pinned to the exact git revision the mining used (2.4.1),
# because an editable install of this poetry tree repairs onto that poetry-core
# revision; every other dependency is pinned to the exact version the image was
# verified against. All pins below were installed and verified together; the
# package-runtime constraint warnings from poetry 2.4.0.dev0 are benign (pip
# reports them for a --no-deps editable install) and the task is verified with
# exactly these versions.
RUN python3 -m venv /opt/poetry-venv \
 && /opt/poetry-venv/bin/pip install "poetry-core @ git+https://github.com/python-poetry/poetry-core.git@b9663e42c808543377ae523611c4cfad68016f30" \
 && cd /app/src \
 && /opt/poetry-venv/bin/pip install -e . --no-deps \
 && /opt/poetry-venv/bin/pip install \
      build==1.6.1 \
      "cachecontrol[filecache]==0.14.4" \
      cleo==2.1.0 \
      dulwich==1.2.14 \
      fastjsonschema==2.22.2 \
      installer==1.0.1 \
      keyring==25.7.0 \
      packaging==26.3 \
      pkginfo==1.13 \
      platformdirs==4.11.8 \
      pyproject-hooks==1.2.0 \
      requests==2.34.2 \
      "requests-toolbelt==1.0.0" \
      shellingham==1.5.4 \
      tomlkit==0.15.1 \
      trove-classifiers==2026.6.1.19 \
      virtualenv==21.7.9 \
      findpython==0.8.0 \
      "pbs-installer[download,install]==2026.9.1" \
      deepdiff==9.1.0 \
      pytest==9.1.1 \
      pytest-mock==3.15.1 \
      "pytest-xdist[psutil]==3.8.0" \
      responses==0.26.3 \
 && /opt/poetry-venv/bin/pip freeze > /opt/pip_freeze.txt

# ---- site-packages manifest: the verifier rejects ANY drift from this      --
# ---- snapshot (catches interpreter hooks such as a planted                ----
# ---- site-packages/sitecustomize.py or .pth shim that would fake the fix) --
# NOTE: computed with the VENV interpreter (the one the trial and verifier
# actually run), so the verifier compares the venv's own site-packages.
RUN /opt/poetry-venv/bin/python - <<'PYEOF'
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

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]

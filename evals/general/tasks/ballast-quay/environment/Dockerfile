# ---------------------------------------------------------------------------
# ballast-quay: pylint's implicit-str-concat check (W1404) fires on an
# implicit concatenation mixing a raw string literal with a non-raw one
# (e.g. [r"\d" "\n"]). Such literals cannot be merged into a single literal,
# so the juxtaposition is deliberate and must not be reported.
#
# The image clones pylint-dev/pylint and checks out upstream PARENT commit
# 2ef1766c3923ee7753cea771959227a35e74972c (immediately before upstream commit
# 16faa29d6bc6ba6533efe426038da62a81ca272b fixed issue #6663), so the agent
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

ARG UPSTREAM_SHA=2ef1766c3923ee7753cea771959227a35e74972c
ARG FIX_SHA=16faa29d6bc6ba6533efe426038da62a81ca272b

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/pylint-dev/pylint.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# files live only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/pylint-dev/pylint.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/functional/i/implicit/implicit_str_concat.py \
      > /opt/golden/implicit_str_concat.py \
 && git show ${FIX_SHA}:tests/functional/i/implicit/implicit_str_concat.txt \
      > /opt/golden/implicit_str_concat.txt \
 && test -s /opt/golden/implicit_str_concat.py \
 && test -s /opt/golden/implicit_str_concat.txt \
 && grep -q "MIXED_RAW1" /opt/golden/implicit_str_concat.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/implicit_str_concat.py /opt/golden/implicit_str_concat.txt

# ---- runtime and test environment, fully pinned (the trial has no network) --
# pylint at this commit is a pure-Python linter: runtime deps astroid/dill/
# isort/mccabe/platformdirs/tomlkit resolve from pyproject.toml constraints
# during `pip install -e .`; the listed test deps mirror the project's own
# requirements_test_min.txt / requirements_test.txt, pinned to exact versions
# (mining used astroid==4.2.0b3; the project tree pins that exact version).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install setuptools==84.0.0 wheel==0.48.0 \
 && cd /app/src \
 && pip install -e . --no-build-isolation \
 && pip install astroid==4.2.0b3 typing-extensions==4.15.0 py==1.11.0 \
              pytest==8.4.2 pytest-benchmark==5.1.0 pytest-timeout==2.4.0 \
              towncrier==26.9.0 requests==2.34.2 pytest-cov==6.3.0 \
              pytest-xdist==3.8.0 six==1.17.0 coverage==7.10.7

# ---- site-packages manifest: the verifier rejects ANY drift from this      --
# ---- snapshot (catches interpreter hooks such as a planted                ----
# ---- site-packages/sitecustomize.py or .pth shim that would fake the fix) --
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

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
# trawler-bowsprit: pypa/setuptools artifact names lose version fidelity
# (upstream issue #4302).
#
# The image clones pypa/setuptools SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), installs it editable so the
# trial's python imports the checked-out tree, extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ through a throwaway bare clone that is deleted, and keeps the
# fix commit out of the shipped repository, so the agent cannot read the
# answer with `git log --all` (it is unreachable; and there is no network at
# trial time).
#
# The golden test extracted from the fix commit is
# setuptools/tests/test_config_discovery.py::TestNoConfig::test_build_with_discovered_name,
# which builds an sdist of a configuration-less project and asserts the
# dist/ns_nested_pkg-0.0.0.tar.gz archive name. Overlaid onto the parent
# tree the module fails exactly once (that node); with the fix applied the
# module is fully green (verified empirically in this image: parent+overlay
# => 1 failed; fixed+overlay => 223 passed across test_config_discovery,
# test_sdist, test_egg_info, test_wheel).
#
# Neither setuptools nor any of its runtime dependencies is a Terminal-Bench
# 2.1 source repository (checked against
# specs/tb21_source_repositories.json).  No submodules are used.
#
# Dependency era pins (April 2024, the fix-commit era) are needed for the
# suite to run clean on this base image:
#   - pytest is pinned to 8.4.2 per the mining entry (pytest 9.x breaks
#     collection of this module on an unrelated deprecation);
#   - wheel must be ~0.42 (newer wheel emits FutureWarning for the
#     externalised bdist_wheel entry point, which the suite's filterwarnings
#     turns into an error);
#   - ruff/pytest-ruff must be era versions (a 2025 ruff flags the golden
#     test file's import block, which upstream's 2024 config accepted);
#   - build-essential provides libc6-dev so the C-extension tests compile.
# `pip install -e '.[testing]'` is how this era declares its test extras
# (setup.cfg [options.extras_require] testing).
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

ARG UPSTREAM_SHA=92b45e9817ae829a5ca5a5962313a56b943cad91
ARG FIX_SHA=df45427cbb67c1149fcf5d2d1e2705e69b3baf0c

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 --branch v69.3.0 https://github.com/pypa/setuptools.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/pypa/setuptools.git \
 && git fetch --depth 1 origin df45427cbb67c1149fcf5d2d1e2705e69b3baf0c \
 && mkdir -p /opt/golden \
 && git show df45427cbb67c1149fcf5d2d1e2705e69b3baf0c:setuptools/tests/test_config_discovery.py \
      > /opt/golden/test_config_discovery.py \
 && test "$(sha256sum /opt/golden/test_config_discovery.py | cut -d' ' -f1)" \
      = "4e26abc25c27b75265f960aadc90cb9d2c20669f8378eafe56410544494c4678" \
 && grep -q 'DEFAULT_VERSION = "0.0.0"' /opt/golden/test_config_discovery.py \
 && ! grep -q 'CANONICAL_DEFAULT_VERSION' /opt/golden/test_config_discovery.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install editable + era-pinned tooling, then hand the tree to uid 1000 --
# The chown lives in the SAME RUN that pip wrote the build artefacts, so the
# bytes are stored once (single layer).
COPY files/ /app/
WORKDIR /app
RUN cd /app/src \
 && pip install -e '.[testing]' \
 && pip install --no-cache-dir 'pytest==8.4.2' 'build==1.2.2.post1' \
        'wheel==0.42.0' 'ruff==0.2.2' 'pytest-ruff==0.3.1' 'coverage==7.16.0' \
 && rm -rf /app/src/build /app/src/setuptools/__pycache__ \
 && chown -R 1000:1000 /app /app/src
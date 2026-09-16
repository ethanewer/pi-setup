# outrigger-ferry: python-poetry/poetry issue #10804 — garbled remediation
# pip command when build-config-settings holds a plain-string value.
#
# The image clones python-poetry/poetry at the PARENT commit
# 378c693f0e63da2c4669b2158c31ecadfa619587 (immediately before upstream
# commit 35eb5025dc7374db74ef26ce32a0e70f54d2e3b6 fixed it), so the agent
# gets the real repository with the real bug still in it. When an install
# fails during the build step, Executor's error path renders the
# remediation `pip wheel ...` command from the package's configured build
# config settings; for a plain-str setting value the code iterates the
# string per character (`for setting_value in config_settings[setting]:`),
# so "CC": "gcc" prints as three per-letter --config-settings flags. The
# fix (upstream #10804) wraps a str value in a list before iterating.
#
# The working clone is created with `git init` + a single `git fetch
# --depth 1 origin <parent-sha>` and left detached there, so the ONLY
# commit object in /app/src/.git is the parent itself; the fix commit is
# unreachable. The golden test (the fix-commit version of
# tests/installation/test_executor.py) is extracted from a THROWAWAY clone
# that is deleted, so the fix bytes never land in the working clone or in
# this task tree.
#
# poetry-core is pinned to the mining run's lock ref
# b9663e42c808543377ae523611c4cfad68016f30 (git+install), and every other
# pip requirement is pinned to exact versions resolved by the base image's
# own interpreter.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT=378c693f0e63da2c4669b2158c31ecadfa619587
ARG UPSTREAM_SHA_FIX=35eb5025dc7374db74ef26ce32a0e70f54d2e3b6
ARG POETRY_CORE_PIN=b9663e42c808543377ae523611c4cfad68016f30

ENV OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# ---- git plumbing ---------------------------------------------------------
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && git config --system init.defaultBranch main

# ---- working clone: the pinned parent commit and nothing else ------------
# Ownership is fixed in the SAME RUN as the clone so the tree is never
# copied into a second layer by a later chown.
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/python-poetry/poetry.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && ! git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && chown -R 1000:1000 /app/src \
 && echo "parent pinned at ${UPSTREAM_SHA_PARENT}; fix unreachable; exactly one commit"

# ---- python toolchain: venv + pinned deps (warm, offline at trial time) ---
# poetry-core is a VCS pin from the mining lock; `-e . --no-deps
# --no-build-isolation` reuses that pinned poetry-core instead of letting
# pip's build isolation fetch a floating one. Remaining deps are exact
# pins resolved on this base image's own interpreter.
RUN python3 -m venv /opt/poetry-venv \
 && /opt/poetry-venv/bin/pip install --no-cache-dir \
      "poetry-core @ git+https://github.com/python-poetry/poetry-core.git@${POETRY_CORE_PIN}" \
 && cd /app/src \
 && /opt/poetry-venv/bin/pip install --no-cache-dir --no-build-isolation -e . --no-deps \
 && /opt/poetry-venv/bin/pip install --no-cache-dir \
      "build==1.6.1" \
      "cachecontrol[filecache]==0.14.4" \
      "cleo==2.1.0" \
      "deepdiff==9.1.0" \
      "dulwich==1.2.14" \
      "fastjsonschema==2.22.2" \
      "findpython==0.8.0" \
      "installer==1.0.1" \
      "keyring==25.7.0" \
      "packaging==26.3" \
      "pbs-installer[download,install]==2026.9.1" \
      "pkginfo==1.13" \
      "platformdirs==4.11.8" \
      "pyproject-hooks==1.2.0" \
      "pytest==9.1.1" \
      "pytest-mock==3.15.1" \
      "pytest-xdist[psutil]==3.8.0" \
      "requests==2.34.2" \
      "requests-toolbelt==1.0.0" \
      "responses==0.26.3" \
      "shellingham==1.5.4" \
      "tomlkit==0.15.1" \
      "trove-classifiers==2026.6.1.19" \
      "virtualenv==21.7.9" \
 && /opt/poetry-venv/bin/python -c \
      "import poetry.installation.executor as _e; assert _e.__file__.startswith('/app/src/src'), _e.__file__" \
 && /opt/poetry-venv/bin/pip list --disable-pip-version-check | grep -E "^(poetry|build) " \
 && echo "venv ready; poetry resolves to the working tree"

# ---- golden test: fix-commit version of tests/installation/test_executor.py -
# Throwaway clone, deleted immediately afterwards. The upstream test bytes
# only ever live at /opt/golden inside the image, and the fix commit never
# exists inside /app/src/.git.
RUN git init -q /tmp/upstream-fix-clone \
 && git -C /tmp/upstream-fix-clone remote add origin https://github.com/python-poetry/poetry.git \
 && git -C /tmp/upstream-fix-clone fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git -C /tmp/upstream-fix-clone show ${UPSTREAM_SHA_FIX}:tests/installation/test_executor.py > /opt/golden/test_executor.py \
 && grep -q "test_build_backend_error_includes_config_settings_in_pip_command" /opt/golden/test_executor.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && ! git -C /app/src cat-file -e "${UPSTREAM_SHA_FIX}^{commit}" \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && echo "golden test extracted; fix commit still unreachable from /app/src"

# ---- pristine pre-fix package bake ----------------------------------------
# The verifier runs the agent's reproduction AND the golden/hidden tests
# against this untouched copy of the parent-era package via PYTHONPATH and
# requires them to fail, proving the symptom is real and lives in the
# shipped source (not in the agent's script).
RUN mkdir -p /opt/pre-fix-poetry \
 && cp -r /app/src/src/poetry /opt/pre-fix-poetry/ \
 && diff -r /app/src/src/poetry /opt/pre-fix-poetry/poetry > /dev/null \
 && PYTHONPATH=/opt/pre-fix-poetry /opt/poetry-venv/bin/python -c \
      "import poetry.installation.executor as e; assert e.__file__.startswith('/opt/pre-fix-poetry'), e.__file__; print('pre-fix copy importable:', e.__file__)" \
 && rm -rf /opt/pre-fix-poetry/poetry/installation/__pycache__ \
 && chmod -R a+rX /opt/pre-fix-poetry \
 && echo "pre-fix package baked and importable via PYTHONPATH"

# ---- parent direction, confirmed in THIS image ----------------------------
# The golden regression test must FAIL on the shipped parent tree (the
# garbled per-character flags), and the authored reproduction must fail on
# both the shipped tree and the pre-fix copy. Network is not used: pytest
# runs with the tree's own fixture-mocked repositories.
RUN set -e \
 && cd /app/src \
 && git config --global --add safe.directory '*' \
 && cp /opt/golden/test_executor.py tests/installation/test_executor.py
RUN set -u; \
    cd /app/src; \
    /opt/poetry-venv/bin/pytest tests/installation/test_executor.py -k "test_build_backend_error_includes_config_settings_in_pip_command" --no-header -p no:randomly -o addopts="" > /tmp/parent-golden.log 2>&1; \
    rc=$?; \
    set -e; \
    echo "golden-on-parent rc=$rc (must be nonzero)"; \
    test $rc -ne 0; \
    grep -q "1 failed" /tmp/parent-golden.log; \
    grep -q "CC=g" /tmp/parent-golden.log; \
    git -C /app/src checkout -q -- tests/installation/test_executor.py; \
    rm -f /tmp/parent-golden.log; \
    echo "parent direction: golden test FAILS on the shipped tree (bug present)"

# ---- fix direction, confirmed in THIS image --------------------------------
# The same golden test must PASS against a THROWAWAY copy of the package
# with the upstream fix applied (never shipped); the reproduction must pass
# against that copy too. The fix bytes only ever exist at /tmp/fixcheck inside
# the build and are deleted afterwards.
RUN set -e \
 && mkdir -p /tmp/fixcheck \
 && cp -r /app/src/src/poetry /tmp/fixcheck/ \
 && /opt/poetry-venv/bin/python - <<'PY'
from pathlib import Path
p = Path('/tmp/fixcheck/poetry/installation/executor.py')
s = p.read_text()
a = "for setting in config_settings:\n                                for setting_value in config_settings[setting]:"
b = "for setting in config_settings:\n                                values = config_settings[setting]\n                                if isinstance(values, str):\n                                    values = [values]\n                                for setting_value in values:"
assert a in s, "anchor line not found"
p.write_text(s.replace(a, b))
print('fix applied to /tmp/fixcheck copy')
PY
RUN set -e \
 && /opt/poetry-venv/bin/python - <<'PY'
from pathlib import Path
s = Path('/tmp/fixcheck/poetry/installation/executor.py').read_text()
assert "if isinstance(values, str):" in s
print('fix anchor present in /tmp/fixcheck copy')
PY
RUN set -e \
 && cd /app/src \
 && cp /opt/golden/test_executor.py tests/installation/test_executor.py \
 && PYTHONPATH=/tmp/fixcheck /opt/poetry-venv/bin/pytest tests/installation/test_executor.py -k "test_build_backend_error_includes_config_settings_in_pip_command" --no-header -p no:randomly -o addopts="" > /tmp/fix-golden.log 2>&1 \
 && grep -q "1 passed" /tmp/fix-golden.log \
 && git checkout -q -- tests/installation/test_executor.py \
 && rm -f /tmp/fix-golden.log \
 && echo "fix direction: golden test PASSES against the fixed copy"

# ---- existing-suite baseline on the pristine parent tree --------------------
# A green baseline for the verifier's "the fix broke nothing else" run.
# Three tests in tests/installation/test_executor.py are excluded: they
# exercise embedded-wheel downloads that do not exist in this environment
# (test_execute_executes_a_batch_of_operations and the two
# test_execute_prints_warning_for_yanked_package params) and fail for
# reasons unrelated to this bug. test_chef.py is excluded too: its
# test_prepare_directory_with_extensions needs a live PEP517 subprocess
# build of a fixture. All other tests here are measured green on this
# image, on both the parent tree and the fixed tree.
RUN cd /app/src \
 && /opt/poetry-venv/bin/pytest tests/installation/test_chooser.py tests/installation/test_chooser_errors.py tests/installation/test_installer.py tests/installation/test_wheel_installer.py tests/packages -q --no-header -p no:randomly -o addopts="" > /tmp/baseline1.log 2>&1; rc=$?; \
    tail -2 /tmp/baseline1.log; \
    test $rc -eq 0 && grep -q "617 passed" /tmp/baseline1.log && rm -f /tmp/baseline1.log \
 && echo "baseline 1 green: chooser+installer+wheel_installer+packages" \
 && /opt/poetry-venv/bin/pytest tests/installation/test_executor.py --no-header -p no:randomly -o addopts="" \
      --deselect "tests/installation/test_executor.py::test_execute_executes_a_batch_of_operations" \
      --deselect "tests/installation/test_executor.py::test_execute_prints_warning_for_yanked_package" \
      -q > /tmp/baseline2.log 2>&1; rc=$?; \
    tail -2 /tmp/baseline2.log; \
    test $rc -eq 0 && grep -q "74 passed" /tmp/baseline2.log && rm -f /tmp/baseline2.log \
 && echo "baseline 2 green: executor minus environment-broken tests"

# ---- reproduce both directions at build time --------------------------------
# The reproduction (the same contract the instruction gives the agent: drive
# poetry's Executor through a build failure for a local directory package
# whose build-config-settings hold one plain-string and one array setting,
# print the remediation pip command, exit 0 iff the whole string appears as a
# single flag) must FAIL on the shipped parent tree and on the pre-fix copy,
# and PASS once the fix is applied to a throwaway copy. The bytes live only
# in this heredoc and in the oracle; they are never shipped to the agent.
RUN cat > /tmp/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for the garbled build-config-settings pip command."""
import sys
from pathlib import Path

from build import BuildBackendException
from cleo.io.buffered_io import BufferedIO
from poetry.config.config import Config
from poetry.installation.executor import Executor
from poetry.installation.operations import Install
from poetry.core.packages.package import Package
from poetry.repositories.repository_pool import RepositoryPool
from poetry.utils.env import MockEnv
from poetry.utils.isolated_build import IsolatedBuildBackendError


def main() -> int:
    project = Path("/app/src/tests/fixtures/simple_project").resolve()
    if not project.is_dir():
        print(f"fixture directory not found: {project}")
        return 2

    cfg = Config()
    cfg.merge(
        {
            "cache-dir": "/tmp/outrigger-repro/cache",
            "data-dir": "/tmp/outrigger-repro/data",
            "installer": {
                "parallel": False,
                "build-config-settings": {
                    "simple-project": {
                        "CC": "gcc",
                        "--build-option": ["--one", "--two"],
                    },
                },
            },
        }
    )

    error = IsolatedBuildBackendError(
        project,
        BuildBackendException(Exception("build failed"), description="build failed"),
    )

    io = BufferedIO()
    executor = Executor(MockEnv(), RepositoryPool(), cfg, io)
    executor._chef.prepare = lambda *a, **k: (_ for _ in ()).throw(error)

    package = Package(
        "simple-project",
        "1.2.3",
        source_type="directory",
        source_url=project.as_posix(),
    )
    executor.execute([Install(package)])

    output = io.fetch_output()
    print(output)

    ok = True
    if "--config-settings='CC=gcc'" not in output:
        print("MISSING: the whole-string setting 'CC=gcc' must appear as ONE flag")
        ok = False
    if "--config-settings='C=C'" in output:
        print("GARBLED: per-character flags for the string value are present")
        ok = False
    if "--config-settings='--build-option=--one'" not in output:
        print("MISSING: array value item '--build-option=--one'")
        ok = False
    if "--config-settings='--build-option=--two'" not in output:
        print("MISSING: array value item '--build-option=--two'")
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
PY
RUN set -u; \
    cd /app/src; \
    git config --global --add safe.directory '*'; \
    /opt/poetry-venv/bin/python /tmp/repro.py > /tmp/repro-shipped.log 2>&1; \
    shipped=$?; \
    PYTHONPATH=/opt/pre-fix-poetry /opt/poetry-venv/bin/python /tmp/repro.py > /tmp/repro-prefix.log 2>&1; \
    prefix=$?; \
    echo "repro on shipped tree rc=$shipped (must be nonzero)"; \
    echo "repro on pre-fix copy rc=$prefix (must be nonzero)"; \
    test $shipped -ne 0; \
    test $prefix -ne 0; \
    grep -q "C=C" /tmp/repro-shipped.log; \
    mkdir -p /tmp/fixcheck; \
    cp -r /app/src/src/poetry /tmp/fixcheck/; \
    /opt/poetry-venv/bin/python - <<'PY'
from pathlib import Path
p = Path('/tmp/fixcheck/poetry/installation/executor.py')
s = p.read_text()
a = "for setting in config_settings:\n                                for setting_value in config_settings[setting]:"
b = "for setting in config_settings:\n                                values = config_settings[setting]\n                                if isinstance(values, str):\n                                    values = [values]\n                                for setting_value in values:"
assert a in s
p.write_text(s.replace(a, b))
print('fix applied to /tmp/fixcheck copy')
PY
RUN set -u; \
    PYTHONPATH=/tmp/fixcheck /opt/poetry-venv/bin/python /tmp/repro.py > /tmp/repro-fixed.log 2>&1; \
    rc3=$?; \
    set -e; \
    echo "repro on fixed copy rc=$rc3 (must be 0)"; \
    test $rc3 -eq 0; \
    grep -q -- "--config-settings='CC=gcc'" /tmp/repro-fixed.log; \
    rm -rf /tmp/fixcheck /tmp/repro.py /tmp/repro-*.log; \
    echo "reproduction verified: fails on shipped+pre-fix, passes on fixed"

# ---- permissions for the trial (uid 1000 or root) ---------------------------
# /app/src is owned by uid 1000 (from the clone RUN). /app and /logs must be
# writable, /opt/golden and /opt/pre-fix-poetry readable by anyone; the venv
# is root-owned but world-readable.
RUN mkdir -p /logs \
 && chmod 777 /logs \
 && chmod 444 /opt/golden/test_executor.py \
 && chmod 555 /opt/golden \
 && chmod -R a+rX /opt/pre-fix-poetry \
 && find /opt/poetry-venv -type d -print0 | xargs -0 chmod 755 \
 && chmod -R a+rX /opt/poetry-venv \
 && echo "permissions set"

WORKDIR /app
CMD ["/bin/bash"]
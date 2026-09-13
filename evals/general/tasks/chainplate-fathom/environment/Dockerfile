# ---------------------------------------------------------------------------
# chainplate-fathom: semgrep leaks GitLab CI job tokens into the project URL
# it reports (upstream issue #9849).
#
# The image clones semgrep/semgrep with ONLY the PARENT commit in the object
# store (a8b650dffe910d7b8903fe05ceeb75fdc7983197, the commit immediately
# before upstream e3062fc251448ffcf16a38245e5e6a8dca894df5 fixed issue
# #9849), so the agent gets the real repository with the real bug still in
# it, and the fix commit is unreachable from /app/src. The one submodule the
# python package needs at runtime (cli/src/semgrep/semgrep_interfaces) is
# checked out. The CLI is installed editable (`pip install -e ./cli`), so
# the agent's edits under /app/src are live with no build or reinstall step.
#
# The project's own regression test for the bug is extracted from the FIX
# commit by a throwaway bare clone (deleted afterwards) into /opt/golden/;
# upstream test bytes never enter this repository's tree (which is
# byte-audited). A build-time smoke run asserts the mined failing state is
# what the image ships: get_project_url() still leaks the token, the fixed
# helper does not exist, and the golden test cannot even collect.
#
# semgrep/semgrep and its one checked-out submodule (returntocorp/
# semgrep-interfaces) are not Terminal-Bench 2.1 source repositories
# (checked against specs/tb21_source_repositories.json; the other ~40
# submodules are shell-history only and are never fetched).
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=a8b650dffe910d7b8903fe05ceeb75fdc7983197
ARG FIX_SHA=e3062fc251448ffcf16a38245e5e6a8dca894df5
ARG GOLDEN_SHA=7d1f46c1e26081e0c2655ecc9e1de6f8ad8c7f475f87922f512603715aa87e8b

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/semgrep/semgrep.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && git -C /app/src submodule update --init cli/src/semgrep/semgrep_interfaces \
 && test -f /app/src/cli/src/semgrep/semgrep_interfaces/lang.json \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, deleted afterwards: the fix commit never exists
# inside /app/src/.git, and the upstream test bytes live only in the image
# at /opt/golden/ (never in this repository's tree).
RUN git init --bare -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/semgrep/semgrep.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:cli/tests/unit/test_clean_project_url.py \
      > /opt/golden/test_clean_project_url.py \
 && test -s /opt/golden/test_clean_project_url.py \
 && test "$(sha256sum /opt/golden/test_clean_project_url.py | cut -d' ' -f1)" \
      = "${GOLDEN_SHA}" \
 && grep -q "def test_git_url_clean" /opt/golden/test_clean_project_url.py \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_clean_project_url.py

# ---- install the CLI editable + pytest (the trial has no network) ----------
RUN cd /app/src \
 && pip install -e ./cli \
 && pip install pytest==8.0.2

# ---- keep predictable build artifacts out of the working-tree diff ----------
RUN printf 'cli/semgrep.egg-info/\ncli/build/\ncli/dist/\ncli/.pytest_cache/\n.pytest_cache/\n__pycache__/\n*.pyc\n' \
    >> /app/src/.git/info/exclude

# ---- build-time proof the image ships the mined failing state ---------------
# At the parent commit get_project_url() returns the remote URL including the
# GitLab CI job token; the fixed helper does not exist (so the upstream
# regression test cannot even collect); and the installed package resolves to
# the checked-out tree. Any of these false and the build fails closed.
RUN mkdir -p /tmp/pubrepo \
 && cd /tmp/pubrepo \
 && git init -q \
 && git remote add origin https://gitlab-ci-token:glcbt-64_wFuiRFQk9t841JHKQnAT@gitlab.company.world/app/test-case.git \
 && leaked="$(python3 -c 'from semgrep.git import get_project_url; print(get_project_url())')" \
 && echo "build-time get_project_url() -> $leaked" \
 && test "$leaked" = 'https://gitlab-ci-token:glcbt-64_wFuiRFQk9t841JHKQnAT@gitlab.company.world/app/test-case.git' \
 && ! python3 -c 'from semgrep.git import clean_project_url' 2>/tmp/import-err.log \
 && grep -q ImportError /tmp/import-err.log \
 && { python3 -m pytest -p no:cacheprovider -q /opt/golden/test_clean_project_url.py >/tmp/golden-parent.log 2>&1 || true; } \
 && grep -q ImportError /tmp/golden-parent.log \
 && python3 -c 'import semgrep; print(semgrep.__file__)' | grep -q '^/app/src/cli/src/semgrep/__init__.py$' \
 && rm -rf /tmp/pubrepo

# The trial may run as an arbitrary uid; open the tree for writes.
RUN chmod -R a+rwX /app/src

WORKDIR /app

CMD ["/bin/bash"]
# yard-sloop: semgrep drops the `_git` segment from Azure DevOps project URLs.
#
# The image clones semgrep/semgrep SHALLOW at the PARENT commit
# e3f9cc50988fb04241c1626e427246538c425314 (the real upstream bug, issue
# #10184, is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit d7a3e3bd43c77edceeff6e8fa5068005d029dac8
# at build time into /opt/golden/ (upstream bytes never enter this task
# tree). The fix commit is fetched only into a throwaway bare clone that is
# deleted, so it is never reachable from /app/src/.git: the working clone is
# created with `git init` + a single `git fetch --depth 1 origin <parent>`
# and left detached there, so exactly ONE commit object exists.
#
# /opt/pristine is a byte-for-byte copy of the working tree as shipped (with
# .git), used by the verifier as the "pre-fix tree concept" to run the
# agent's own reproduction against. Both /opt/golden and the two pristine
# source files are sha256-guarded inside tests/test.sh, because the trial
# can run as root and could otherwise rewrite them.
#
# Pure-Python fix: `pip install -e ./cli` plus pinned pytest==8.4.2. The
# semgrep_interfaces submodule is initialised so `import semgrep.meta` works.
# No network is needed at trial time. The build finishes with a fail-closed
# smoke pass: the mined symptom (golden regression test fails at parent) must
# reproduce here, or the build stops.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=e3f9cc50988fb04241c1626e427246538c425314
ARG FIX_SHA=d7a3e3bd43c77edceeff6e8fa5068005d029dac8
ARG GOLDEN_SHA256=6f77c1745e72dd6ec57c9d0ef6a74875b32ea7816c1e0b59e465448b37bfede0

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# (chmod piggybacked into this layer so no second copy of the tree exists)
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/semgrep/semgrep.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && cd /app/src \
 && git submodule update --init cli/src/semgrep/semgrep_interfaces \
 && test -f cli/src/semgrep/semgrep_interfaces/__init__.py \
 && chmod -R a+rwX /app/src

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway bare clone, deleted afterwards, so the fix object never enters
# /app/src/.git. The golden file's sha256 is asserted here and re-checked by
# the verifier, and it is world-readable so any trial uid can run it.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/semgrep/semgrep.git \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:cli/tests/default/e2e-pro/test_meta.py > /opt/golden/test_meta.py \
 && test -s /opt/golden/test_meta.py \
 && grep -q "test_git_url_parser" /opt/golden/test_meta.py \
 && grep -q "dev.azure.com/test/TestName/_git/Core.Thing" /opt/golden/test_meta.py \
 && test "$(sha256sum /opt/golden/test_meta.py | cut -d' ' -f1)" = "${GOLDEN_SHA256}" \
 && chmod -R a+rwX /opt/golden \
 && cd / && rm -rf /tmp/fixsrc

# ---- pristine pre-fix reference tree (verifier's "pre-fix concept") ---------
RUN cp -a /app/src /opt/pristine \
 && chmod -R a+rwX /opt/pristine

# ---- install (warm every cache at build time; the trial must not need the
#      network even though this host may have egress) -------------------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/pycache

RUN cd /app/src \
 && pip install -e ./cli \
 && pip install --no-cache-dir pytest==8.4.2

# ---- fail closed: the mined bug must reproduce in THIS image ----------------
# The golden (fixed-era) regression test must FAIL on the parent-era tree and
# the parser must show the buggy URL; if upstream ever moves so that either
# stops, the build stops rather than shipping a task whose oracle can't pass.
RUN cd /tmp \
 && { python3 -m pytest /opt/golden/test_meta.py -q -p no:cacheprovider > /tmp/golden-parent.log 2>&1; \
      grep -q "1 failed" /tmp/golden-parent.log; } \
 && rm -f /tmp/golden-parent.log \
 && python3 - <<'EOF'
from semgrep.meta import get_url_from_sstp_url
assert get_url_from_sstp_url('https://test@dev.azure.com/test/TestName/_git/Core.Thing') == 'https://dev.azure.com/test/TestName/Core.Thing'
EOF

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
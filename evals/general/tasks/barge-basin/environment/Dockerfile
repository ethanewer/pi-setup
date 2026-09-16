# ---------------------------------------------------------------------------
# barge-basin: bandit logs "Bandit internal error" with a list-index-out-of-
# range traceback when scanning valid Python that passes an empty list to one
# of the standard-library subprocess helpers, instead of scanning it normally.
#
# The image clones PyCQA/bandit and checks out upstream PARENT commit
# ad56c78f1e2f7d56fb3f75e8c2d78da85292d0e0 (immediately before upstream commit
# 049eba08c90c86404d16ed71e5f109dfddf459cd fixed issue #1141 via PR #1146),
# so the agent gets the real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src. The upstream regression material
# (the fix-commit revision of tests/functional/test_functional.py and the
# example line it depends on) is extracted through a SEPARATE throwaway clone
# under /tmp that is deleted afterwards, so the fix bytes never enter the
# shipped repository.
#
# A pristine copy of the buggy parent tree is kept at /opt/pretree so the
# verifier can prove the agent's own reproduction fails against the pre-fix
# code and passes against the repaired tree.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=ad56c78f1e2f7d56fb3f75e8c2d78da85292d0e0
ARG FIX_SHA=049eba08c90c86404d16ed71e5f109dfddf459cd

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/PyCQA/bandit.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- pristine pre-fix tree for the verifier's two-tree checks ---------------
# Captured before any package install so it contains only the parent tree.
# Content-pinned: the decision-relevant plugin file must keep the exact bytes
# of the parent revision (6ac8944...), so a tampered /opt/pretree cannot
# invalidate the pre-fix checks.
RUN cp -a /app/src /opt/pretree \
 && chmod -R a+rX /opt/pretree \
 && test "$(git -C /opt/pretree rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(sha256sum /opt/pretree/bandit/plugins/injection_shell.py | cut -d' ' -f1)" = \
        "6ac89442e38ff67cc3cd1b5c88c72e31ebacf339ce2b03fb6905850dda63c1b6"

# ---- extract the upstream regression material from the FIX commit ----------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git or /opt/pretree/.git. Upstream bytes also never enter this
# repository; the golden files live only in the image at /opt/golden/.
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/PyCQA/bandit.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show ${FIX_SHA}:tests/functional/test_functional.py \
      > /opt/golden/test_functional.py \
 && git -C /tmp/fixsrc show ${FIX_SHA}:examples/subprocess_shell.py \
      > /opt/golden/subprocess_shell.py \
 && test -s /opt/golden/test_functional.py \
 && test -s /opt/golden/subprocess_shell.py \
 && grep -q "def test_subprocess_shell" /opt/golden/test_functional.py \
 && grep -q "subprocess.check_output(\[\], stdout=None)" /opt/golden/subprocess_shell.py \
 && test "$(sha256sum /opt/golden/test_functional.py | cut -d' ' -f1)" = \
        "9d1392f5de3731ada360fcafa8f9ea17688a3b2e0d5218f435a310740506149a" \
 && test "$(sha256sum /opt/golden/subprocess_shell.py | cut -d' ' -f1)" = \
        "e57fa980c54aff45b49883db2ebc4b6ddbe6fa85cee9d860cf826b0feaa2ad2c" \
 && cd / \
 && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/*.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
# bandit 1.7.9-dev-era is pure Python: no compiled extensions, nothing fetched
# at runtime. pbr computes the install version from the git tree (setup.py is
# `setuptools.setup(pbr=True)`), so git must exist and the clone must be in
# place BEFORE the editable installs run -- which it is.
# The project's own test suite (stestr) needs: coverage, fixtures, stestr,
# testscenarios, testtools, beautifulsoup4 (requirements of the python-subunit
# test runner stack) plus the sarif extra so tests/unit/formatters/test_sarif.py
# imports. All resolved against bench-base:python-3.12 and pinned.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install setuptools==84.0.0 pbr==7.0.3 wheel==0.48.0 \
        stevedore==5.9.1 PyYAML==6.0.3 rich==15.0.0 \
        GitPython==3.1.62 sarif-om==1.0.4 jschema-to-python==1.2.3 \
        coverage==7.16.0 fixtures==4.3.2 stestr==4.2.1 testscenarios==0.7.0 \
        testtools==2.9.1 beautifulsoup4==4.15.0 pytest==8.3.5 \
 && cd /app/src \
 && pip install --no-build-isolation -e . \
 && pip install --no-build-isolation -e '.[baseline]' \
 && pip install --no-build-isolation -e '.[sarif]'

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
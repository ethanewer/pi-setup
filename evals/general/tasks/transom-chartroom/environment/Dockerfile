# transom-chartroom: psf/requests accepts header names/values that end with a
# newline (upstream issue #7308, "Fix cosmetic header validity parsing
# regex").
#
# The image clones psf/requests SHALLOW at the PARENT commit (the real bug is
# present in the working tree at /app/src and requests is installed editable
# from it), extracts the project's own regression test
# tests/test_requests.py::TestRequests::test_header_no_return_chars FROM THE
# FIX COMMIT into /opt/golden/ at build time, and captures a pristine copy of
# the whole parent tree into /opt/prefix/ so the verifier can run the agent's
# reproduction against the un-fixed code. The fix commit is fetched only into
# a throwaway bare clone under /tmp that is deleted, so the fix object is
# never reachable from /app/src (build asserts `! git cat-file -e
# ${FIX_SHA}^{commit}` twice: right after the working clone and again after
# the throwaway fetch). psf/requests is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json); nothing
# is pip-installed from git, and the only internet fetches at build time are
# github.com (clone) and pypi.org (pinned wheels incl. the pytest-httpbin /
# httpbin stack that the project's own regression test needs).
#
# Measured on this host: ~12 s build at 1 CPU (--cpuset-cpus 0), 648 MB
# unique image size. At parent the repro is accepted and the golden test
# fails 3 of 13 parametrized cases ({"foo":"bar\n"}, {"foo\n":"bar"},
# {"foo":"\n"}); after the upstream fix the repro raises InvalidHeader for
# all five trailing-return cases and the golden test passes 13/13.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=4443b1a847b190010c2972a658924b98b5db6360
ARG FIX_SHA=bc7dd0fc4d56e808bcdd85ac2d797b3107c89259

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/psf/requests.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 4443b1a847b190010c2972a658924b98b5db6360 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- pinned install: project (editable, with its socks extra) + tooling -----
# Every package pinned exactly. httpbin/pytest-httpbin are only needed so the
# project's own regression test (which drives requests.get against the local
# httpbin fixture) can run inside the verifier; loopback works with no
# network. Wheel/egg caches are discarded so nothing lingers for the trial.
RUN cd /app/src \
 && python3 -m pip install --no-cache-dir -e '.[socks]' \
       urllib3==2.7.0 certifi==2026.7.22 charset_normalizer==3.5.1 \
       idna==3.19 PySocks==1.7.1 \
       pytest==9.1.1 pytest-httpbin==2.1.0 httpbin==0.10.4 \
       flask==3.1.3 werkzeug==3.1.8 \
 && python3 -c "import requests; assert requests.__file__.startswith('/app/src/'), requests.__file__"

# ---- pristine parent tree for the verifier's bug-present repro run ----------
# Frozen at build time from the same shallow clone (git archive HEAD); the
# verifier runs /app/reproduce_header_newline_bug.py with this tree on
# sys.path ahead of the installed copy and requires the script to fail,
# proving the reproduction really captures the bug.
RUN mkdir -p /opt/prefix \
 && git -C /app/src archive --format=tar HEAD | tar -x -C /opt/prefix \
 && test -f /opt/prefix/src/requests/_internal_utils.py

# ---- extract the fix-commit regression test via a throwaway clone -----------
# /tmp/fixsrc is a throwaway bare clone that is rm -rf'd after extraction, so
# the fix object never enters /app/src/.git; the build asserts it afterwards.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/psf/requests.git \
 && git fetch --depth 1 origin bc7dd0fc4d56e808bcdd85ac2d797b3107c89259 \
 && mkdir -p /opt/golden \
 && git show bc7dd0fc4d56e808bcdd85ac2d797b3107c89259:tests/test_requests.py \
      > /opt/golden/test_requests.py \
 && test "$(sha256sum /opt/golden/test_requests.py | cut -d' ' -f1)" \
      = "c78ee6c624468dfb2d974a74a9e9e9192029516e6dcdbf5e69a1e90f6a389c30" \
 && grep -q "def test_header_no_return_chars" /opt/golden/test_requests.py \
 && cd / && rm -rf /tmp/fixsrc \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}"

# The build above ran as root; open the tree for whichever uid the trial uses
# (the agent must edit library sources and pytest writes caches into tests/).
# The requests tree is small, so the copied layer is a few MB, not a
# duplicate of a large build.
RUN chmod -R a+rwX /app/src

WORKDIR /app
CMD ["/bin/bash"]
# skiff-beacon: falconry/falcon URL decoding corrupts a literal '+' followed
# by two hex digits when unquote_plus is disabled (upstream issue #2670).
#
# The image clones falcon SHALLOW at the PARENT commit (the real upstream bug
# is present in the working tree) and compiles the Cython extension in place,
# so the shipped tree exhibits the mined failing state: the direct probe
# decode('+00', unquote_plus=False) yields '\x00', and the upstream regression
# test extracted from the FIX commit fails exactly two of its parametrized
# variants. The fix commit is fetched only into a throwaway bare clone under
# /tmp that is deleted at build time, so the fix is never reachable from
# /app/src/.git (verified with ! git cat-file -e "${FIX_SHA}^{commit}").
# The fixed upstream regression test is shipped to /opt/golden/test_utils.py
# for the verifier to run against the repaired tree.
#
# /opt/pristine is a second shallow clone at the same parent commit with its
# own in-place compiled extension, made read-only: the verifier runs the
# agent's /app/repro.py against it to prove the reproduction detects the
# pre-fix behaviour. falconry/falcon is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
#
# Measured on the host: full build ~55 s wall on many cores (apt + pip
# downloads dominate; build_ext itself is ~6 s), image ~1.0 GB. The trial
# never rebuilds more than a single extension module (~2 s at 1 CPU).
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=6566f4a4254fcc0158635c2e3bd4983663070ae4
ARG FIX_SHA=7f55a5eb2e10b96d83ecc57384d4c8dca8bc4221

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Exact pins resolved against bench-base:python-3.12's own interpreter and
# index. falcon's setup.py needs setuptools and Cython to cythonize its
# falcon.cyutil modules; pytest runs the shipped + golden suites.
RUN pip3 install --no-cache-dir \
     setuptools==84.0.0 \
     wheel==0.48.0 \
     Cython==3.3.0 \
     pytest==8.4.2

# ---- working clone: buggy parent commit, fix commit unreachable -------------
RUN git clone --depth 1 https://github.com/falconry/falcon.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 6566f4a4254fcc0158635c2e3bd4983663070ae4 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && echo "working clone pinned to the parent commit; fix object absent"

# ---- compile the extension in place so the bug is live; open the tree -------
# chmod stays in this RUN so the built tree is not copied into a second layer.
RUN cd /app/src \
 && python3 setup.py build_ext --inplace \
 && rm -rf build \
 && PYTHONPATH=/app/src python3 -c "\
from falcon.cyutil.uri import decode; \
r = decode('+00', unquote_plus=False); \
assert r != '+00', 'mined failing state is not present in /app/src'; \
print('failing state present:', repr(r))" \
 && chmod -R a+rwX /app/src

# ---- extract the upstream regression test from the FIX commit -----------------
# Throwaway bare clone in /tmp: the fix object never exists inside
# /app/src/.git, and the shipped /opt/golden file is sha256-checked against
# the blob extracted here.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin 7f55a5eb2e10b96d83ecc57384d4c8dca8bc4221 \
 && mkdir -p /opt/golden \
 && git show 7f55a5eb2e10b96d83ecc57384d4c8dca8bc4221:tests/test_utils.py \
      > /opt/golden/test_utils.py \
 && test "$(sha256sum /opt/golden/test_utils.py | cut -d' ' -f1)" \
      = "01737d5e7cc255d8690b454cf81173c18b8b2890a80449593b940845de19193b" \
 && grep -q "A plus followed by two hex digits must not be" \
      /opt/golden/test_utils.py \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod -R a=rX /opt/golden

# ---- pristine pre-fix tree (verifier target for the agent's repro) ----------
# Same parent commit, own compiled extension, read-only. chmod stays in this
# RUN so the built tree is not copied into a second layer.
RUN git clone --depth 1 https://github.com/falconry/falcon.git /opt/pristine \
 && cd /opt/pristine \
 && git fetch --depth 1 origin 6566f4a4254fcc0158635c2e3bd4983663070ae4 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && python3 setup.py build_ext --inplace \
 && rm -rf build \
 && PYTHONPATH=/opt/pristine python3 -c "\
from falcon.cyutil.uri import decode; \
r = decode('+00', unquote_plus=False); \
assert r != '+00', 'pristine tree is not exhibiting the bug'; \
print('pristine failing state present:', repr(r))" \
 && chmod -R a=rX /opt/pristine \
 && chmod 0555 /opt/pristine

# ---- smoke: shipped suite slice is green at the parent (unrelated tests) ----
RUN cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q tests/test_utils.py 2>&1 | tail -1
RUN cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q tests/test_query_params.py 2>&1 | tail -1
RUN cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q tests/test_cython.py 2>&1 | tail -1

# ---- smoke: the upstream regression fails at the parent, exactly as mined ---
RUN cd /app/src \
 && PYTHONPATH=/app/src PYTHONPYCACHEPREFIX=/tmp/goldpycache python3 -m pytest -q \
      -p no:cacheprovider /opt/golden/test_utils.py \
      -k uri_decode_unquote_plus 2>&1 | tee /tmp/golden-smoke.log | tail -2 \
 && grep -q "2 failed" /tmp/golden-smoke.log \
 && rm -rf /opt/golden/__pycache__ /opt/golden/.pytest_cache /tmp/goldpycache

WORKDIR /app
CMD ["/bin/bash"]
# cockboat-caboose: psf/requests -- a Content-Type header parameter without an
# equals sign (e.g. "text/html; charset") crashes encoding resolution.
#
# The image clones psf/requests and checks out upstream PARENT commit
# bc7dd0fc4d56e808bcdd85ac2d797b3107c89259 (immediately before upstream commit
# f0198e6dfc431a2293dc16e1b1e8fcddc910a7f3 fixed issue #7309), so the agent
# gets the real repository with the real bug still in it. See the golden-test
# extraction below, which uses a throwaway clone that is deleted, so the fix
# commit and its bytes never land in the working clone.
#
# The image also keeps a pristine copy of the same parent tree at
# /opt/prefix-src (a plain directory, no .git). The verifier runs the agent's
# own reproduction against that pristine tree to prove the reproduction really
# does demonstrate the bug, and against the repaired /app/src tree to prove
# the fix resolved it.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=bc7dd0fc4d56e808bcdd85ac2d797b3107c89259
ARG FIX_SHA=f0198e6dfc431a2293dc16e1b1e8fcddc910a7f3

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
# The parent is fetched by SHA from a fresh init so the object store contains
# exactly one commit -- the parent -- and nothing else (neither the fix commit
# nor any later tree).
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/psf/requests.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git and upstream bytes never enter this repository. The golden
# file lives only in the image at /opt/golden/.
RUN git clone -q --depth 1 --no-checkout https://github.com/psf/requests.git /tmp/goldensrc \
 && git -C /tmp/goldensrc fetch -q --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/goldensrc show ${FIX_SHA}:tests/test_utils.py \
      > /opt/golden/test_utils.py \
 && test -s /opt/golden/test_utils.py \
 && grep -q 'text/html; charset' /opt/golden/test_utils.py \
 && ! grep -q '"no_equals": True' /opt/golden/test_utils.py \
 && rm -rf /tmp/goldensrc \
 && chmod a+r /opt/golden/test_utils.py

# ---- pristine pre-fix tree for the verifier's reproduction check ------------
RUN cp -a /app/src /opt/prefix-src \
 && rm -rf /opt/prefix-src/.git \
 && chmod -R a+rX /opt/prefix-src

# ---- pinned test/runtime dependencies (v43c slot entry pins) ----------------
# The project is installed editable so the trial's `import requests` resolves
# to the agent's own checkout. The pins are the exact versions the bug was
# verified against; requests itself is the local checkout (2.33.0 at the
# pinned commit).
ENV PIP_NO_CACHE_DIR=1
RUN python3 -m pip install 'urllib3==2.7.0' 'certifi==2026.7.22' \
            'charset_normalizer==3.5.1' 'idna==3.19' 'PySocks==1.7.1' \
            'pytest==9.1.1' \
 && cd /app/src && python3 -m pip install -e '.[socks]' \
 && python3 -c "import requests, sys; assert sys.version_info[:2] == (3, 12)"

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app \
 && rm -rf /app/src/src/requests/__pycache__ /app/src/tests/__pycache__

CMD ["/bin/bash"]
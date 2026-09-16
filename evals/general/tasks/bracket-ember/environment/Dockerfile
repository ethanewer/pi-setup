# bracket-ember: requests JSONDecodeError cannot be pickled and unpickled.
#
# The image clones psf/requests SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, so it is NOT reachable from the depth-1 clone the
# agent works on, and it is fetched through a throwaway bare clone that is
# deleted. Pure-Python library: no compilation.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=96b22fa18c00831656ee4b286bf1c9062459b00a
ARG FIX_SHA=3ff3ff21dd45957c9e143cd500291959bb15f690

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable -------------
# A depth-1 clone of main cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/psf/requests.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 96b22fa18c00831656ee4b286bf1c9062459b00a \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
# tests/__init__.py, compat.py and utils.py are copied too so the extracted
# test module's relative imports resolve when run as a package from
# /opt/golden. The regression test is the only thing selected at run time.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/psf/requests.git \
 && git fetch --depth 1 origin 3ff3ff21dd45957c9e143cd500291959bb15f690 \
 && mkdir -p /opt/golden/tests/testserver \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/__init__.py \
      > /opt/golden/tests/__init__.py \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/compat.py \
      > /opt/golden/tests/compat.py \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/utils.py \
      > /opt/golden/tests/utils.py \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/test_requests.py \
      > /opt/golden/tests/test_requests.py \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/testserver/__init__.py \
      > /opt/golden/tests/testserver/__init__.py \
 && git show 3ff3ff21dd45957c9e143cd500291959bb15f690:tests/testserver/server.py \
      > /opt/golden/tests/testserver/server.py \
 && test -s /opt/golden/tests/test_requests.py \
 && grep -q "test_json_decode_errors_are_serializable_deserializable" \
           /opt/golden/tests/test_requests.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) -------------
# Dependency pins come from the mining entry; every pin resolves against this
# base image's own interpreter.
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir \
        urllib3==2.7.0 \
        certifi==2026.7.22 \
        charset_normalizer==3.5.1 \
        idna==3.19 \
        PySocks==1.7.1 \
        pytest==9.1.1 \
 && cd /app/src \
 && pip install --no-cache-dir -e '.[socks]' \
 && python3 -c "import requests; assert 'src/requests' in requests.__file__, requests.__file__" \
 && python3 -c "import pytest; print('pytest', pytest.__version__)"

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
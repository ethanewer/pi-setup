# bracket-buoy: psutil reports the host's own address as the broadcast
# address of a /32 "single-host" IPv4 network (real upstream bug #2964).
#
# The image clones giampaolo/psutil SHALLOW at the PARENT commit (the bug is
# present in the working tree; the fix commit ef3d9af is a later upstream
# commit and is never fetched into the working clone, so it is unreachable
# from /app/src) and extracts the project's own regression test from the FIX
# commit at build time into /opt/golden/ (upstream bytes never enter this
# repository). The golden extraction uses a throwaway bare clone that is
# deleted afterwards.
#
# The psutil C extension (psutil._psutil) is compiled in place by
# `pip install -e .`; gcc and Linux headers come from apt.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=8a5d53df33e28831f4833803b89e40e857d5632d
ARG FIX_SHA=ef3d9af1062e3e5d59e431e957b75fd4287b053e

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- build toolchain for the C extension --------------------------------
RUN apt-get update \
 && apt-get install -y gcc libc6-dev linux-libc-dev \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable ----------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the
# parent by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/giampaolo/psutil.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 8a5d53df33e28831f4833803b89e40e857d5632d \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/giampaolo/psutil.git \
 && git fetch --depth 1 origin ef3d9af1062e3e5d59e431e957b75fd4287b053e \
 && mkdir -p /opt/golden \
 && git show ef3d9af1062e3e5d59e431e957b75fd4287b053e:tests/test_misc.py \
      > /opt/golden/test_misc.py \
 && test -s /opt/golden/test_misc.py \
 && grep -q "def test_broadcast_addr_single_host" /opt/golden/test_misc.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN pip install --no-cache-dir pytest==9.1.1 pytest-instafail==0.5.0 pytest-xdist==3.8.0 \
 && cd /app/src \
 && pip install --no-cache-dir -e .

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
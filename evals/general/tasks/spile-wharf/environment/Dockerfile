# spile-wharf: giampaolo/psutil — swap_memory() crashes with ValueError
# ("invalid literal for int() with base 10: b'kB'") when /proc/meminfo
# contains a field printed without a space after its colon (upstream issue
# #2809, fixed upstream by commit d46726028ac01e27e052ec60371951e789d2b101).
#
# The image SHALLOW-clones psutil at the PARENT commit 5ec16ad4 and
# pip-installs it in editable mode (the C extension is prebuilt as a cached
# layer; the agent's fix is pure Python, so no rebuild is ever needed), then
# extracts the project's own regression test (tests/test_linux.py at the FIX
# commit) through a THROWAWAY clone under /tmp which is deleted afterwards,
# and overlays that file into the working tree exactly as the mining
# reproduction did, so
#     python -m pytest tests/test_linux.py::TestSwapMemory::test_no_space_after_colon
# FAILS inside the image with the mined symptom. The smoke step below fails
# the build if that failure is not present. The fix commit is fetched only
# into the throwaway clone and is never reachable from /app/src (asserted
# both ways in this file). /opt/pristine is a read-only copy of the PRISTINE
# parent tree with its extension prebuilt, used by the verifier and the
# oracle to run a reproduction against a pre-fix tree.
FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=5ec16ad4d887c069f6b758fd0659fb6bc9b47f7d
ARG FIX_SHA=d46726028ac01e27e052ec60371951e789d2b101
ARG GOLDEN_SHA=ed21926713e0b2e4c7aef75e2889d9792675818252eeb89ec0f7b6b0bda80754

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain + test dependencies -------------------------------------
# gcc + libc6-dev + linux-libc-dev: psutil's C extension needs stdlib.h and
# linux/ethtool.h to compile (measured: gcc alone is not enough). pytest,
# pytest-instafail and pytest-xdist are required by the project's own
# [tool.pytest] addopts (-p instafail, -p xdist). All pins were resolved
# against this base image's interpreter; running the suite serially (no -n)
# keeps everything on one CPU.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev linux-libc-dev \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir pytest==9.1.1 pytest-instafail==0.5.0 pytest-xdist==3.8.0

# --- working clone: buggy PARENT commit, fix commit unreachable --------------
# Shallow clone + shallow fetch of the parent; HEAD is asserted against the
# pin so the build fails closed if upstream moves; the fix object must not
# exist in this clone. The editable install prebuilds the C extension; the
# final chmod (same layer as the install, so nothing is copied twice) makes
# the tree writable for the trial user.
RUN git clone --depth 1 https://github.com/giampaolo/psutil.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 5ec16ad4d887c069f6b758fd0659fb6bc9b47f7d \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src' \
 && pip install --no-cache-dir -e . --force-reinstall --no-deps --quiet \
 && chmod -R a+rwX /app/src

# --- extract the upstream regression test from the FIX commit -----------------
# Throwaway clone under /tmp (deleted in this same RUN), so the fix commit
# never enters /app/src/.git — an agent cannot read the answer with
# `git log --all`. The sha256 pin proves the extracted file is the exact
# upstream file; /opt/golden is made read-only.
RUN git init /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/giampaolo/psutil.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin d46726028ac01e27e052ec60371951e789d2b101 \
 && mkdir -p /opt/golden \
 && git -C /tmp/fixsrc show d46726028ac01e27e052ec60371951e789d2b101:tests/test_linux.py \
      > /opt/golden/test_linux.py \
 && test "$(sha256sum /opt/golden/test_linux.py | cut -d' ' -f1)" = "$GOLDEN_SHA" \
 && grep -q "def test_no_space_after_colon" /opt/golden/test_linux.py \
 && chmod -R a-w /opt/golden \
 && rm -rf /tmp/fixsrc

# --- overlay the corrected regression test into the working tree --------------
# Exactly what the mining reproduction did: `git checkout <fix> -- tests/test_linux.py`.
RUN cp /opt/golden/test_linux.py /app/src/tests/test_linux.py

# --- bake in the mined failing state (the build fails if the bug is absent) ---
RUN cd /app/src \
 && python -m pytest tests/test_linux.py::TestSwapMemory::test_no_space_after_colon \
      -p no:cacheprovider > /tmp/smoke.log 2>&1; \
    grep -q "ValueError: invalid literal for int() with base 10: b'kB'" /tmp/smoke.log

# --- pristine PRE-FIX tree with prebuilt extension, read-only -----------------
# A byte copy of the parent tree (buggy code, C extension prebuilt). The
# verifier and oracle point PYTHONPATH at it to run a reproduction against a
# pre-fix tree. It carries no fix and is unwritable for the trial user.
RUN cp -a /app/src /opt/pristine \
 && chmod -R a-w /opt/pristine \
 && chmod a+rX /opt/pristine \
 && chmod 755 /opt/pristine /opt/pristine/psutil /opt/pristine/tests

WORKDIR /app

CMD ["/bin/bash"]
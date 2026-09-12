# cistern-cinder: psutil's virtual_memory() crashes with
# ValueError: invalid literal for int() with base 10: b'kB' when /proc/meminfo
# contains a field with no space after its colon (arm64 ShadowCallStack fields,
# upstream issue #2809).
#
# The image clones giampaolo/psutil and checks out the PARENT commit (the real
# upstream bug is present in the working tree). The project's own regression
# test is extracted from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository), and the fix-commit copy of
# tests/test_linux.py is overlaid onto the working tree exactly as the mining
# reproduction did, so
#   pytest tests/test_linux.py::TestVirtualMemoryMocks::test_virtual_memory_no_space_after_colon
# fails inside the image with the mined symptom. The fix commit is fetched
# only into a throwaway bare clone that is deleted, so it is never reachable
# from /app/src/.git, which holds a single shallow fetch of the parent.
#
# Dependency pins from the verified issue: none (the project has no external
# runtime deps). The suite runner is pytest 9.1.1 plus the two plugins the
# project's own [tool.pytest] addopts require (pytest-instafail 0.5.0,
# pytest-xdist 3.8.0). Building the C extension needs gcc + the Linux kernel
# header packages from the issue's install recipe.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=afaaf9f340ff6561541f9f4781c58268b59abdac
ARG FIX_SHA=8d8ffe516627c024ccd216485b5920e8ffa8a88e

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- toolchain needed to build psutil's C extension (issue install recipe) --
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev linux-libc-dev \
 && rm -rf /var/lib/apt/lists/*

# ---- working clone: buggy parent commit, fix commit unreachable -------------
# A depth-1 fetch of exactly the parent SHA, so the fix commit (a descendant
# of the parent on upstream master) can never be reachable from this clone.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/giampaolo/psutil.git \
 && git fetch --depth 1 origin afaaf9f340ff6561541f9f4781c58268b59abdac \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/giampaolo/psutil.git \
 && git fetch --depth 1 origin 8d8ffe516627c024ccd216485b5920e8ffa8a88e \
 && mkdir -p /opt/golden \
 && git show 8d8ffe516627c024ccd216485b5920e8ffa8a88e:tests/test_linux.py \
      > /opt/golden/test_linux.py \
 && test -s /opt/golden/test_linux.py \
 && grep -q "test_virtual_memory_no_space_after_colon" /opt/golden/test_linux.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the regression test into the working tree -----------------------
# The tree's tests/test_linux.py is exactly the fix-commit copy, so the mined
# `-k no_space_after_colon` reproduction matches. The overlay is the only
# pre-existing working-tree modification besides the harness-owned files.
RUN cp /opt/golden/test_linux.py /app/src/tests/test_linux.py \
 && cd /app/src \
 && test "$(git diff --name-only)" = "tests/test_linux.py" \
 && cmp -s /opt/golden/test_linux.py tests/test_linux.py \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- install (warm every cache at build time; trial is offline) --------------
# pytest-instafail and pytest-xdist are required by the project's own
# [tool.pytest] addopts (--instafail, -p instafail, -p xdist).
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1
RUN pip install --no-cache-dir pytest==9.1.1 \
 && pip install --no-cache-dir pytest-instafail==0.5.0 \
 && pip install --no-cache-dir pytest-xdist==3.8.0 \
 && pip install --no-cache-dir -e /app/src

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

# ---- fail closed: the mined symptom must reproduce inside THIS image ---------
# The golden test must FAIL and the direct PROCFS_PATH repro must raise the
# same ValueError, before the image is accepted for the trial.
RUN cd /app/src \
 && python3 -m pytest tests/test_linux.py::TestVirtualMemoryMocks::test_virtual_memory_no_space_after_colon \
      -q -p no:cacheprovider > /tmp/warm-golden.log 2>&1; \
    rc=$?; test "$rc" -ne 0 \
 && grep -q "ValueError" /tmp/warm-golden.log \
 && python3 /app/probe_meminfo.py > /tmp/warm-probe.log 2>&1; \
    rc=$?; test "$rc" -ne 0 \
 && grep -q "ValueError" /tmp/warm-probe.log \
 && rm -f /tmp/warm-golden.log /tmp/warm-probe.log

CMD ["/bin/bash"]
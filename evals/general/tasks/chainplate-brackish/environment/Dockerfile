# chainplate-brackish: pylint-dev/pylint protected-access false positive for
# self.__class__ (upstream issue #11160, fixed by 0f39f39e0).
#
# The trial gets the REAL upstream repository checked out at the PARENT
# commit, where the bug is still present. The fix commit is never fetched
# into /app/src; the project's own regression test for the bug is extracted
# from the fix commit into /opt/golden using a throwaway clone that is
# deleted immediately afterwards.
ARG UPSTREAM_SHA_PARENT=9242406e364f537f91e99564400944f685f8b079
ARG UPSTREAM_SHA_FIX=0f39f39e04a3114900877e08a8310a1aaf2e8237

FROM bench-base:python-3.12

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Regardless of which uid the trial runs as, git must treat /app/src as safe.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the parent commit with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds ONLY the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/pylint-dev/pylint.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Extract the project's OWN regression test for this bug (the functional test
# that the fix commit appends to) into /opt/golden using a THROWAWAY clone
# that is deleted immediately afterwards, so upstream test bytes never land
# in this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/pylint-dev/pylint.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/functional/a/access/access_to_protected_members.py > /opt/golden/access_to_protected_members.py \
 && git show ${UPSTREAM_SHA_FIX}:tests/functional/a/access/access_to_protected_members.txt > /opt/golden/access_to_protected_members.txt \
 && test -s /opt/golden/access_to_protected_members.py \
 && test -s /opt/golden/access_to_protected_members.txt \
 && grep -q "self.__class__._attr" /opt/golden/access_to_protected_members.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Install pylint editable from the parent tree, then pin every dependency to
# the exact versions the mining run verified (astroid==4.2.0b4 is the
# project's own test-min pin and is required: it is the astroid release the
# bug reproduces with). Everything is baked in; the trial has no network.
WORKDIR /app/src
RUN python3 -m pip install --no-cache-dir -e . \
 && python3 -m pip install --no-cache-dir \
      astroid==4.2.0b4 \
      typing-extensions==4.15.0 \
      py==1.11.0 \
      pytest==8.4.2 \
      pytest-benchmark==5.1.0 \
      pytest-timeout==2.4.0 \
      requests==2.34.2 \
      pytest-cov==7.1.0 \
      pytest-xdist==3.8.0 \
      six==1.17.0 \
      coverage==7.16.0 \
 && python3 -c "import astroid, pylint; print('astroid', astroid.__version__, '| pylint', pylint.__version__)"

# The image is built as root; the trial may run as root or as uid 1000.
# Pure-Python project: no compile step, but the agent must be able to edit
# the working tree, so make /app (including /app/src) writable by everyone.
RUN chmod -R a+rwX /app/src && chmod -R a+rwX /app

COPY files/ /app/
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
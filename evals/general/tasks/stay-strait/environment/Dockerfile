ARG UPSTREAM_SHA_PARENT=6cd33dceed60949e2dbc32e3f0f5e67c4c882e1e
ARG UPSTREAM_SHA_FIX=d097a23bfaa85b4f37c771d30358e8fb5adacd7f

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Pure C build (the mining run's recipe, unchanged). The build is
# self-configuring; `git` itself is installed only because a couple of the
# project's build/test scripts fall back to it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential libssl-dev zlib1g-dev libcurl4-openssl-dev \
      libexpat1-dev gettext libpcre2-dev file unzip git \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository (git/git) at exactly the parent commit,
# with the shallowest possible history: `git init` + one depth-1 fetch of the
# pinned SHA means the object store in /app/src holds ONLY the parent commit.
# The fix commit (which an agent must not be able to look up or fetch) is
# NEVER fetched into this clone; it is asserted unreachable below.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/git/git.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "parent pin ok: $(git rev-parse HEAD)"

# Warm build at the parent commit (~2.5 minutes on one core). The trial has
# no network, so this layer IS the warm tree: the agent edits one C file and
# only needs an incremental `make -j1` to relink. Fail closed if the build
# fails or dirties the tracked tree. The ownership change and the pristine
# PRE-FIX binary copy live in the SAME RUN as the build that produced the
# files: a layer is written once, so moving chown into this RUN costs
# nothing, while a chown in its own later RUN would store the tree twice.
RUN cd /app/src && make -j1 > /tmp/warm-make.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-make.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -x /app/src/git \
 && test -z "$(git status --porcelain)" \
 && mkdir -p /opt/prefix \
 && cp /app/src/git /opt/prefix/git \
 && chmod 755 /opt/prefix/git \
 && test -x /opt/prefix/git \
 && chown -R 1000:1000 /app/src \
 && echo "warm build ok, tree clean, prefix binary baked, tree handed to uid 1000"

# Parent-direction confirmation 1/2 in THIS image: the project's own local
# clone suite (t/t5605-clone-local.sh) must pass all its 20 tests at the
# parent commit when run as uid 1000, proving the test machinery and the
# permissions work for the user the trial may run as.
RUN su -s /bin/bash ubuntu -c 'cd /app/src/t && ./t5605-clone-local.sh' \
        > /tmp/t5605-parent.log 2>&1; rc=$?; \
    tail -4 /tmp/t5605-parent.log; \
    if [ $rc -ne 0 ]; then echo "t5605 AT PARENT FAILED (exit $rc)"; exit 1; fi; \
    grep -q "passed all 20 test(s)" /tmp/t5605-parent.log \
 || { echo "t5605 did not pass all 20 tests"; exit 1; }

# Parent-direction confirmation 2/2 in THIS image: the direct reproduction.
# A local repository with one commit and a corrupt loose ref file (contents
# not a valid object id); a direct local-path clone of that repository on
# the freshly built binary must abort with the refs.c BUG diagnostic instead
# of failing gracefully.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
export HOME=/home/ubuntu GIT_CONFIG_NOSYSTEM=1
GB=/app/src/git
tmp=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
"$GB" init -q "$tmp/corrupt" || exit 1
( cd "$tmp/corrupt" \
  && "$GB" config user.email t@t \
  && "$GB" config user.name t \
  && echo one > one \
  && "$GB" add one \
  && "$GB" commit -q -m one ) || exit 1
echo a > "$tmp/corrupt/.git/refs/heads/topic" || exit 1
( cd "$tmp" && "$GB" clone corrupt working > "$tmp/out" 2>&1 )
rc=$?
echo "direct repro rc=$rc"
cat "$tmp/out" | head -6
if [ "$rc" -eq 0 ]; then echo "REPRO DID NOT FAIL - failing closed"; exit 1; fi
grep -q "create called without valid new_oid" "$tmp/out" \
    || { echo "BUG diagnostic not seen"; exit 1; }
rm -rf "$tmp"
echo "parent-direction: bug reproduces in this exact image"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && su -s /bin/bash ubuntu -c '/tmp/reprocheck.sh' \
 && rm -f /tmp/reprocheck.sh

# Extract the project's own regression test for this bug (the 21st test the
# fix commit appends to t/t5605-clone-local.sh) into /opt/golden using a
# THROWAWAY clone that is deleted in the same RUN afterwards, so the fix
# commit never lands in /app/src and no upstream test bytes enter this task
# tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/git/git.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:t/t5605-clone-local.sh \
      > /opt/golden/t5605-clone-local.sh \
 && test -s /opt/golden/t5605-clone-local.sh \
 && grep -q "local clone from repo with corrupt refs fails gracefully" \
      /opt/golden/t5605-clone-local.sh \
 && grep -q "has a null OID" /opt/golden/t5605-clone-local.sh \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone. The
# object store holds exactly one commit (the parent), so both the commit
# object and every blob changed by the fix are absent.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Record sha256 pins of the golden test, of the pre-fix binary, and of the
# build/test toolchain itself, so the verifier can detect substitution. The
# trial and the verifier both run the compiled binary and the project's own
# test scripts; an adversarial root agent could otherwise swap the compiler
# or the test shell for a stub that fakes a green run. /opt is read-only for
# everyone afterwards.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/t5605-clone-local.sh > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/git > /opt/pins/prefix-git.sha256 \
 && sha256sum /usr/bin/gcc /usr/bin/cc /usr/bin/make /usr/bin/ld \
                 /usr/bin/git /usr/bin/bash /usr/bin/dash \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/t5605-clone-local.sh \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 7 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-git.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

# The tree is owned by uid 1000 throughout (set in the warm-build RUN
# above), so root and uid 1000 can both build and test in it; no separate
# chmod layer is needed, which would have stored the ~2.5 GB tree twice.

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]
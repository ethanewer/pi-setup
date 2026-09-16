ARG UPSTREAM_SHA_PARENT=d9d677b2d8cc5f70499db04e633ba7a400f64cbf
ARG UPSTREAM_SHA_FIX=c39952b925ccf59e49f3c174861a862dc1721492

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

# Warm build at the parent commit (~2 minutes on one core). The trial has no
# network, so this layer IS the warm tree: the agent edits one C file and
# only needs an incremental `make -j1` to relink. Fail closed if the build
# fails or dirties the tracked tree.
#
# The chown/chmod happen in the SAME RUN as the build. Docker layers are
# copy-on-write: a separate `RUN chown -R 1000:1000 /app/src` after a build
# that filled /app/src would write a second full copy of the tree into its
# own layer (measured: 6.73 GB image with two 2.74 GB layers). Merged here,
# the ownership change is recorded once, in the layer that already holds the
# tree. The image is built as root and the trial may run as root or as
# uid 1000 (user `ubuntu` exists in the base image), so every build-time
# writable path is chowned to uid 1000 from the start.
RUN cd /app/src && make -j1 > /tmp/warm-make.log 2>&1; rc=$?; \
    tail -3 /tmp/warm-make.log; \
    if [ $rc -ne 0 ]; then echo "WARM BUILD FAILED (exit $rc)"; exit 1; fi; \
    test -x /app/src/git \
 && test -z "$(git status --porcelain)" \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && echo "warm build ok, working tree clean"

# Bake a pristine PRE-FIX `git` binary (built at the parent commit above) at
# /opt/prefix/git. The verifier runs the agent's own reproduction against
# this binary and requires it to FAIL, proving the symptom is real and that
# the reproduction targets it.
RUN mkdir -p /opt/prefix \
 && cp /app/src/git /opt/prefix/git \
 && test -x /opt/prefix/git \
 && chmod 755 /opt/prefix/git

# Parent-direction confirmation 1/2 in THIS image: the project's own
# fetch --multiple suite (t/t5514-fetch-multiple.sh) must pass all its 12
# tests at the parent commit when run as uid 1000, proving the test
# machinery and the permissions work for the user the trial may run as.
RUN su -s /bin/bash ubuntu -c 'cd /app/src/t && ./t5514-fetch-multiple.sh' \
        > /tmp/t5514-parent.log 2>&1; rc=$?; \
    tail -4 /tmp/t5514-parent.log; \
    if [ $rc -ne 0 ]; then echo "t5514 AT PARENT FAILED (exit $rc)"; exit 1; fi; \
    grep -q "passed all 12 test(s)" /tmp/t5514-parent.log \
 || { echo "t5514 did not pass all 12 tests"; exit 1; }

# Parent-direction confirmation 2/2 in THIS image: the direct reproduction.
# Two bare remotes with one branch each, plus an empty repo with both added
# as remotes; `git fetch --multiple --jobs=0` on the freshly built binary
# must crash with the run-processes BUG diagnostic instead of fetching.
RUN cat > /tmp/reprocheck.sh <<'SH'
#!/bin/bash
set -u
export HOME=/home/ubuntu GIT_CONFIG_NOSYSTEM=1
tmp=$(mktemp -d /tmp/reprocheck.XXXXXX) || exit 1
for r in one two; do
    git init -q --bare "$tmp/$r" || exit 1
    wt=$(mktemp -d /tmp/wt.XXXXXX) || exit 1
    git init -q "$wt" || exit 1
    ( cd "$wt" \
      && git config user.email t@t && git config user.name t \
      && echo hi > f && git add f && git commit -q -m m \
      && git push -q "$tmp/$r" HEAD:master ) || exit 1
    rm -rf "$wt"
done
git init -q "$tmp/test" || exit 1
( cd "$tmp/test" \
  && git remote add one "$tmp/one" \
  && git remote add two "$tmp/two" ) || exit 1
( cd "$tmp/test" && /app/src/git fetch --multiple --jobs=0 > "$tmp/out" 2>&1 )
rc=$?
echo "direct repro rc=$rc"
cat "$tmp/out" | head -5
if [ "$rc" -eq 0 ]; then echo "REPRO DID NOT CRASH - failing closed"; exit 1; fi
grep -q "must provide a non-zero number of processes" "$tmp/out" \
    || { echo "BUG diagnostic not seen"; exit 1; }
rm -rf "$tmp"
echo "parent-direction: bug reproduces in this exact image"
SH
RUN chmod 755 /tmp/reprocheck.sh \
 && su -s /bin/bash ubuntu -c '/tmp/reprocheck.sh' \
 && rm -f /tmp/reprocheck.sh

# Extract the project's own regression test for this bug (the 13th test the
# fix commit appends to t/t5514-fetch-multiple.sh) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so the fix commit
# never lands in /app/src and no upstream test bytes enter this task tree.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/git/git.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:t/t5514-fetch-multiple.sh \
      > /opt/golden/t5514-fetch-multiple.sh \
 && test -s /opt/golden/t5514-fetch-multiple.sh \
 && grep -q "git fetch --multiple --jobs=0 picks a default" \
      /opt/golden/t5514-fetch-multiple.sh \
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
 && sha256sum /opt/golden/t5514-fetch-multiple.sh > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/git > /opt/pins/prefix-git.sha256 \
 && sha256sum /usr/bin/gcc /usr/bin/cc /usr/bin/make /usr/bin/ld \
                 /usr/bin/git /usr/bin/bash /usr/bin/dash \
      > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/t5514-fetch-multiple.sh \
 && test "$(wc -l < /opt/pins/toolchain.sha256)" = 7 \
 && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix-git.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix binary + toolchain pinned"

COPY files/ /app/
RUN chmod a+rwX /app && chmod 644 /app/README-BUILD.md

WORKDIR /app

CMD ["/bin/bash"]
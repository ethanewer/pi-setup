# crosstrees-trough: real upstream tmux tree with a genuine, verified defect.
#
# The tree is pinned by SHA to 936bb6e7, the master revision at which the
# regression for tmux GitHub issue 5511 (variation-selector-widened characters
# dropped in panes with a nonzero x offset) was observed failing. The fix
# commit 696a16cc (landed on master as merge c1f947a3) is the oracle; none of
# its objects may exist in the shipped clone, so the agent cannot read the
# answer with git. The project's own regression test (regress/tty-draw-line.sh)
# is extracted through a separate throwaway clone and deleted afterwards.

FROM bench-base:ubuntu-24.04

WORKDIR /app

# tmux build dependencies (apt is deliberately not version-pinned in this suite).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libtool pkg-config bison byacc \
        libevent-dev libncurses-dev libutempter-dev \
 && rm -rf /var/lib/apt/lists/*

ARG UPSTREAM_SHA=936bb6e7cdff4fc7700a4f36a6b828b87d9f8241
ARG FIX_SHA=696a16cca27408f7d073d097efa4f763b614aef9
ARG FIX_TREE_SHA=c1f947a3c5bc72a40c32dead736f84c4628791ec
ARG GOLDEN_SHA256=1d5231897c32f83c96c861edfd43c4d1a40c31901f854be68ce2c659eebcc92b

# Real upstream tree at the pinned buggy revision, fetched shallow (depth 1) by
# exact SHA so the working clone contains exactly one commit. Fail closed if the
# SHA is not the tip of the fetch. The fix commit must NOT be reachable.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/tmux/tmux.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git checkout -q FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin \
 && git config --system --add safe.directory '*' \
 && git config --system user.email build@localhost \
 && git config --system user.name build \
 && echo "clone-pinned ${UPSTREAM_SHA:0:12}, fix ${FIX_SHA:0:12} absent, no remote"

# Build once here so the agent's rebuild is incremental. The ownership change
# is in the SAME RUN so it never copies the tree into a second layer.
RUN cd /app/src && ./autogen.sh && ./configure >/tmp/configure.log 2>&1 \
 && make -j1 >/tmp/make.log 2>&1 \
 && chown -R 1000:1000 /app/src \
 && mkdir -p /app /logs \
 && chown 1000:1000 /app /logs \
 && echo "build-ok"

# Extract the project's OWN regression test for this defect from the fix-side
# commit through a throwaway clone under /tmp, verified byte-for-byte, then
# delete the clone so the fix object never enters the shipped repository. The
# verifier runs this canonical copy; its content is identical to the copy that
# already ships inside regress/ at the pinned revision.
RUN mkdir -p /opt/golden \
 && git clone --quiet --depth 1 https://github.com/tmux/tmux.git /tmp/golden-clone \
 && cd /tmp/golden-clone \
 && git fetch --quiet --depth 1 origin ${FIX_TREE_SHA} \
 && git checkout -q FETCH_HEAD \
 && test -f regress/tty-draw-line.sh \
 && test "$(sha256sum regress/tty-draw-line.sh | awk '{print $1}')" = "${GOLDEN_SHA256}" \
 && cp regress/tty-draw-line.sh /opt/golden/ \
 && chmod 755 /opt/golden/tty-draw-line.sh \
 && rm -rf /tmp/golden-clone \
 && test ! -e /tmp/golden-clone \
 && echo "golden-extracted"
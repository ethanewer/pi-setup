ARG UPSTREAM_SHA=c60730422e758ef1cebe7aeddf2dda31c996bf04

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=c60730422e758ef1cebe7aeddf2dda31c996bf04

# Toolchain for the CaDiCaL configure+make build (C/C++).
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc g++ make git \
 && rm -rf /var/lib/apt/lists/*

# Real upstream tree, pinned to the immutable 40-hex commit. Shallow: the
# release history is unneeded, this task only drives the solution.
# The tree is then chmod'd in THIS SAME RUN, because the trial must be able
# to write into /app as root or uid 1000 and a `chmod -R` in a later RUN
# would re-store every file into a new copy-on-write layer. The modes set
# here (files 666, directories/executables 777, all root-owned) are exactly
# what the task has always shipped.
RUN git clone --depth 1 https://github.com/arminbiere/cadical.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && chmod -R a+rwX /app

# Warm the whole build as an image layer: configure + full single-CPU
# compile. The solver binaries are then removed, so the agent must re-run
# the project's own build (`make -j1` relinks from the warm objects in a
# few seconds) and place the binary at /app/cadical. The verifier always
# executes the agent-built artifact, never a solver binary shipped in the
# image. The project's OWN proof checker (the standalone lrat-trim that
# ships in the clone's test suite) is compiled here from the pinned source
# into /opt/lrat-trim; the verifier uses it to independently validate every
# UNSAT proof the agent emits, so a forged/corrupted/self-authored proof can
# never pass via the agent's own binary.
# umask 000: everything configure/make creates lands directly at mode 666
# (files) / 777 (executables) -- the same bits the verifier relies on -- so
# the build outputs never need a later chmod layer that would re-store them.
RUN cd /app/src && umask 000 && ./configure \
 && make -j1 \
 && test -x build/cadical \
 && rm -f build/cadical build/mobical \
 && make -j1 >/dev/null \
 && test -x build/cadical \
 && rm -f build/cadical build/mobical \
 && echo "warm-relink-ok"

# Compile the project's own standalone LRAT proof checker from the pinned
# clone, and smoke-test it: a minimal UNSAT instance (empty clause) must be
# reported VERIFIED. lrat-trim is a checker only, not a solver, so it can
# never serve as the /app/cadical deliverable.
RUN gcc -O2 -o /opt/lrat-trim /app/src/test/cnf/lrat-trim.c \
 && chmod 0755 /opt/lrat-trim \
 && printf 'p cnf 1 2\n1 0\n-1 0\n' > /tmp/smoke.cnf \
 && { echo '3 0 1 2 0'; } > /tmp/smoke.lrat \
 && /opt/lrat-trim /tmp/smoke.cnf /tmp/smoke.lrat | grep -q 's VERIFIED' \
 && rm -f /tmp/smoke.cnf /tmp/smoke.lrat \
 && echo "lrat-trim-smoke-ok"

WORKDIR /app

COPY files/ /app/

# Writable by whatever uid (root or 1000) the trial runs as. Only /app/cases
# needs a chmod here: it is four small fixtures fresh from the COPY above, so
# this touches kilobytes. The cloned tree and the warm build were given their
# (identical) modes in the RUNs that created them, so nothing big is ever
# stored twice.
RUN chmod -R a+rwX /app/cases && echo "ferrule-berth build-ok"
# corbel-stave: fix a seeded routing regression in falcon 4.3.1, keep its
# own suite green, and ship a contract-compliant WSGI app.
#
# Pure-Python runtime: falcon's Cython speedups are optional and are disabled
# (FALCON_DISABLE_CYTHON=1), so no C toolchain is needed and no Cython
# extension is compiled.
FROM bench-base:python-3.12

# The 40-hex commit the 4.3.1 tag peels to (the annotated tag object itself
# is not the source tree). Clone --depth 1 --branch GETS the peeled commit;
# we fail closed if upstream ever moves.
ARG UPSTREAM_SHA=e18c27f454b58041c9a48e921f75182aa204d8a9

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

RUN git clone --depth 1 --branch 4.3.1 https://github.com/falconry/falcon.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

# Seed one regression in the compiled URI router: the per-level ordering of
# competing route nodes (literal > complex-var > simple-var) is removed, so
# route resolution becomes registration-order dependent. This patch is the
# ONLY difference from upstream and is authored by us.
COPY files/seed-routing-regression.patch /tmp/seed-routing-regression.patch
RUN cd /app/src \
 && patch -p1 < /tmp/seed-routing-regression.patch \
 && rm -f /tmp/seed-routing-regression.patch \
 && ! grep -q "nodes = sorted" falcon/routing/compiled.py \
 && grep -q "Sort nodes in this sequence" falcon/routing/compiled.py

ENV FALCON_DISABLE_CYTHON=1 \
    PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Warm every cache: pytest (the only test dependency falcon declares) and an
# editable install of the checkout, so agent edits under /app/src/falcon/ are
# live at trial time and pytest runs fully offline.
RUN pip install --no-cache-dir pytest==8.3.5 \
 && cd /app/src \
 && pip install --no-cache-dir -e .

WORKDIR /app

COPY files/ /app/

# The trial may run as uid 1000; the agent must be able to edit /app/src.
RUN chmod -R a+rwX /app

CMD ["/bin/bash"]
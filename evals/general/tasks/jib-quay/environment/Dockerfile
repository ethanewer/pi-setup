# jib-quay — FX transfer hub with a seeded lock-ordering inversion.
#
# Ships a threaded transfer service (/app/service.py), a load driver
# (/app/driver.py), and the visible ledger/mix fixtures.  Byte-identical
# pristine copies are kept at /opt/pristine/ for the verifier: it re-runs
# the ORIGINAL service under each hidden mix to prove the seeded deadlock
# reproduces, and hash-checks both trees so nothing can be weakened.

FROM bench-base:python-3.12

WORKDIR /app
COPY files/ /app/

# Pristine reference copies for the grader's negative probe and integrity
# checks.  Root-owned and read-only so the trial user cannot tamper with
# them (the verifier also hash-checks them against frozen digests).
RUN mkdir -p /opt/pristine \
    && cp /app/service.py       /opt/pristine/service.py \
    && cp /app/driver.py        /opt/pristine/driver.py \
    && cp /app/ledger.json      /opt/pristine/ledger.json \
    && cp /app/mix_visible.json /opt/pristine/mix_visible.json \
    && chown -R root:root /opt \
    && chmod -R a-w /opt/pristine

# Fixture syntax sanity at build time.
RUN python3 -c "import ast; [ast.parse(open(p).read()) for p in ['/app/service.py', '/app/driver.py']]; print('fixture syntax OK')"

CMD ["/bin/bash"]
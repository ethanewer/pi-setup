# sable-vellum — card-classification eval wiring runtime.
#
# Ships a pure-python micro harness package (vellum_eval), the tiny vex-nano
# model and a visible classification corpus. No network is needed at run or
# verify time (pip installs are satisfied from the local tree / base image).
FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Install the importable harness package (vellum_eval) from the copied source
# tree; PyYAML comes from the base image cache. No build isolation so the
# already-present setuptools is reused.
RUN pip install --no-cache-dir --quiet setuptools \
    && pip install --no-cache-dir --quiet pyyaml \
    && pip install --no-cache-dir --quiet --no-build-isolation -e /app/harness

RUN python3 -c "import vellum_eval; print('vellum_eval', vellum_eval.__version__)"

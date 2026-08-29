FROM bench-base:python-3.12
WORKDIR /app

# Fixtures (model, data, board) + the pure-python harness package are baked in.
COPY files/ /app/

# CPU-only. Install PyYAML, then install the importable harness package
# (granite_eval) from the copied source tree (no build isolation, setuptools
# already present in the base image).
RUN pip install --no-cache-dir --quiet setuptools \
    && pip install --no-cache-dir --quiet pyyaml \
    && pip install --no-cache-dir --quiet --no-build-isolation -e /app/harness

RUN python3 -c "import granite_eval; print('granite_eval', granite_eval.__version__)"
FROM bench-base:python-3.12

WORKDIR /app

# Fixtures (model, data) + the pure-python harness package are baked in.
COPY files/ /app/

# Install the importable harness package (no build isolation; setuptools is
# already present in the base image).
RUN pip install --no-cache-dir --quiet setuptools==84.0.0 \
    && pip install --no-cache-dir --quiet pyyaml==6.0.3 \
    && pip install --no-cache-dir --quiet --no-build-isolation -e /app/harness

RUN python3 -c "import fen_eval; print('fen_eval', fen_eval.__version__)"

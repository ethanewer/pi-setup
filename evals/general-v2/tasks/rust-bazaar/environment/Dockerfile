FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch plus the data stack used by the pipeline and the verifier.
RUN pip install --no-cache-dir numpy pandas \
 && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the base snapshot and the visible fold at build time, keep a
# pristine copy for the verifier's no-modify check, then remove the generator
# so the concrete data-generation rule is not discoverable in the container.
RUN python3 /app/gen_data.py \
 && rm -f /app/gen_data.py && rm -rf /app/__pycache__ \
 && mkdir -p /opt/pristine \
 && cp /app/base_snapshot.pt /app/data/line_fold.csv /opt/pristine/

# The agent must never find tests/ or solution/ inside the image.

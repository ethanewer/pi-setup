FROM bench-base:python-3.12

WORKDIR /app

# Data stack used by the scorer and the verifier (deliberately NO torch: the
# frozen model is plain numpy and the memory cap assumes a lean runtime).
RUN pip install --no-cache-dir numpy pandas

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the model and the visible trace set at build time, keep a
# pristine copy for the verifier's no-modify check, then remove the generator
# so the concrete data-generation rule is not discoverable in the container.
RUN python3 /app/gen_data.py \
 && rm -f /app/gen_data.py && rm -rf /app/__pycache__ \
 && mkdir -p /opt/pristine \
 && cp /app/model.npz /app/data/traces_visible.csv /opt/pristine/

# The agent must never find tests/ or solution/ inside the image.

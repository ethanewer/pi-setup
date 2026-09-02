FROM bench-base:python-3.12

WORKDIR /app

# CPU training stack: torch for the model/snapshot, numpy for the fixtures.
RUN pip install --no-cache-dir --disable-pip-version-check \
    numpy \
    torch==2.13.0

# Build-time-only dataset/config generator.
COPY files/ /app/

# Materialize the visible training fixture set, then remove the generator (and
# any stray bytecode) so the concrete data-generation rule is not discoverable
# inside the live container.
RUN python3 /app/gen_data.py \
 && rm -f /app/gen_data.py \
 && rm -rf /app/__pycache__

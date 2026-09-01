FROM bench-base:python-3.12

# CPU-only torch plus the data stack used by the deliverable and the verifier.
RUN pip install --no-cache-dir --disable-pip-version-check numpy pandas \
 && pip install --no-cache-dir --disable-pip-version-check torch --index-url https://download.pytorch.org/whl/cpu

WORKDIR /app

# Build-time fixtures: the deployed base model + one drifted calibration fold.
COPY files/ /app/

# Materialize the base snapshot and the visible fold, then remove the
# generator so the regime rule is not discoverable in the live container.
RUN python3 /app/gen_fixtures.py \
 && rm -f /app/gen_fixtures.py \
 && rm -rf /app/__pycache__

FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch plus the data stack used by the fixtures and the verifier.
RUN pip install --no-cache-dir numpy pandas \
 && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by the deliverable contract and the verifier.
ENV CORAL_FEATURES=20 CORAL_HIDDEN=32 CORAL_CLASSES=2

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the frozen triage model and the visible bag file at build time,
# then remove the generator (and stray bytecode) so nothing beyond the frozen
# snapshot itself is discoverable inside the live container.
RUN python3 /app/gen_buoy.py && rm -f /app/gen_buoy.py && rm -rf /app/__pycache__

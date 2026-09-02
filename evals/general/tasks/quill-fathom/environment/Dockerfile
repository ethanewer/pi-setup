FROM bench-base:python-3.12

WORKDIR /app

# CPU-only torch plus the data stack used by the fixtures and the verifier.
RUN pip install --no-cache-dir numpy pandas \
 && pip install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu

# Architecture constants shared by the deliverable contract and the verifier.
ENV QUILL_FEATURES=16 QUILL_HIDDEN=24 QUILL_CLASSES=3

# Provided fixtures and the (build-time only) generator script.
COPY files/ /app/

# Materialize the frozen base checkpoint and the visible press fold at build
# time, then remove the generator (and stray bytecode) so the concrete
# fold-rule parameters are not discoverable inside the live container.
RUN python3 /app/gen_press.py && rm -f /app/gen_press.py && rm -rf /app/__pycache__

FROM bench-base:python-3.12
WORKDIR /app

# Python ML libs used by the deliverable and the fixtures.
RUN python3 -m pip install --no-cache-dir torch transformers safetensors

# Generate the visible fixtures (/app/pretrained_lm, /app/state_seed.pkl,
# /app/base_clf, /app/data) and the hidden verifier fixtures (/buildout/hidden).
COPY files/fix_gen.py /build/fix_gen.py
RUN python3 /build/fix_gen.py && rm -rf /build

# The agent works in /app and is expected to add /app/workflow.py and
# /app/artifact.
WORKDIR /app
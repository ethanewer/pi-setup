# kite-mesa - CPU-only discrete gridworld RL lab.
FROM bench-base:python-3.12
WORKDIR /app

# numpy is used by the verifier's reference computations (allowed for the
# deliverable too, though pure Python suffices).
RUN pip install --no-cache-dir --disable-pip-version-check numpy

COPY files/ /app/

# RIDGE bag-attention classifier task image.
# CPU-only, pure-python autograd DL framework (numpy). No GPU, no X, no systemd.
FROM bench-base:python-3.12

WORKDIR /app

# numpy is the only runtime dependency (the framework is built from numpy,
# not from a prebuilt ML library).
RUN pip install --no-cache-dir numpy

# Seed the RIDGE framework (deliberately defective: naive attention softmax +
# a wrong-sign objective gradient) and the training entrypoint.
COPY files/ /app/

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]
FROM bench-base:python-3.12

WORKDIR /app

# onnx (graph parsing), onnxruntime (verifier-side reference), numpy. All
# install from PyPI through the corporate CA proxy baked into bench-base.
RUN pip install --no-cache-dir --quiet \
        numpy \
        onnx \
        onnxruntime

COPY files/ /app/

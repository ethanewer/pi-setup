FROM bench-base:python-3.12
# tundra-keystone: concurrency & parallel-execution gap task.
# CPU-only torch (loopback/gloo build) + numpy; small image.
RUN pip install --no-cache-dir --quiet numpy \
 && pip install --no-cache-dir --quiet torch --index-url https://download.pytorch.org/whl/cpu
WORKDIR /app
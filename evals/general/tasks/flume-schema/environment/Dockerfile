# flume-schema — tool-agent platform environment.
#
# Ships the mock agent platform under /app/runtime (deterministic mock model,
# JSON-schema tool registry and the in-memory tool store), the 6-tool schema
# registry and the visible session transcript.  The agent writes the executor
# loop (/app/agent_loop.py) that drives the platform.  Nothing here needs
# pip/apt: pure stdlib, single CPU.

FROM bench-base:python-3.12

WORKDIR /app
COPY files/ /app/

# byte-compile and import the platform before the agent arrives; this both
# proves the image is coherent and fails the build early if a fixture regresses.
RUN python3 -m py_compile /app/runtime/*.py && \
    python3 -c "import sys; sys.path.insert(0, '/app'); import runtime.protocol, runtime.registry, runtime.backend, runtime.models; print('flume-schema platform import ok')"
FROM bench-base:python-3.12

# Harbor Gasket -- maritime analytics research environment with dependency
# provisioning. Keep the build lean and under the 5-minute budget: a C
# toolchain (to build the shipped swellkit source tree) plus networking
# tooling are the only OS-level additions. All heavy packages (torch CPU,
# onnxruntime, the hydra-submitit plugin) are provisioned by the SOLVER into
# /app/venv at solve time, exactly as the reference competency demands.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        build-essential \
        python3-venv \
        curl \
        >/dev/null 2>&1 \
 && rm -rf /var/lib/apt/lists/*

# Ship the fixtures: the swellkit source tree (/app/src), the import-check
# helper (/app/kit), the reference constituents (/app/data) and the pinned
# toolchain release artifact (/app/releases).
WORKDIR /app
COPY files/ /app/

ENV PYTHONUNBUFFERED=1

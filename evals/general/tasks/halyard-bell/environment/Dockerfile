# Halyard yard — task environment.
#
# Ships the Halyard yard repository (with real git history, built below),
# Prometheus tooling for validating alerting rules, and a pytest runner for
# the application's own suite.  The agent writes /app/alerting/alerts.yml.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# prometheus ships promtool; pytest beats the python3-unittest wrapper for a
# filesystem-installed test suite; git is needed to build the shipped history.
RUN apt-get update \
 && apt-get install -y --no-install-recommends prometheus python3-pytest git \
 && rm -rf /var/lib/apt/lists/*

# The trial runs as uid 1000 against a repo created at build time.
RUN git config --system --add safe.directory '*'
RUN git config --system user.email "build@localhost" \
 && git config --system user.name "build"

COPY files/ /app/

WORKDIR /app

# Generate the fixture repository history and prove its tests are green.
RUN bash /app/build_repo.sh \
 && rm -f /app/build_repo.sh \
 && cd /app/yard \
 && PYTHONPATH=/app/yard/src python3 -m pytest -q

# The agent's deliverable directory (does not exist until the agent creates
# the rules file that must live there).
RUN mkdir -p /app/alerting

# cpus=1: any numeric thread pool must be pinned to one.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

FROM bench-base:python-3.12
WORKDIR /app

# setuptools is pre-installed so the vendored prismval harness can be pip
# installed OFFLINE at run time with --no-build-isolation (the agent must
# perform that install; the harness is intentionally not installed here).
RUN pip install --no-cache-dir --quiet setuptools

COPY files/ /app/

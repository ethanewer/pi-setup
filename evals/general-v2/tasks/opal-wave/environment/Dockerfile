FROM bench-base:python-3.12

# numpy is used by the verifier for spectral property checks (and is allowed
# for the deliverable).
RUN pip install --no-cache-dir --disable-pip-version-check numpy

WORKDIR /app

COPY files/ /app/

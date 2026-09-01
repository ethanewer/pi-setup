FROM bench-base:python-3.12

# Only numpy is needed: the engine must be dependency-free beyond stdlib+numpy.
RUN pip install --no-cache-dir numpy

WORKDIR /app

COPY files/ /app/

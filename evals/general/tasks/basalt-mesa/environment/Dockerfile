FROM bench-base:python-3.12

# numpy only: the solver must be stdlib+numpy, nothing else.
RUN pip install --no-cache-dir numpy

WORKDIR /app

COPY files/ /app/

FROM bench-base:python-3.12

WORKDIR /app

# The POST /score endpoint is served with Flask.
RUN pip install --no-cache-dir flask

COPY files/ /app/

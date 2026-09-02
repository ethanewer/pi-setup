FROM bench-base:python-3.12

WORKDIR /app

# Flask is the web framework required by the /triage endpoint.
RUN pip install --no-cache-dir flask

COPY files/ /app/

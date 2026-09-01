FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir pandas python-dateutil

# Visible fixture data (the "live system"). The agent/oracle consumes this.
COPY files/ /app/data/
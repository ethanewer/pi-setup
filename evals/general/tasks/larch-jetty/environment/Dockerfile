FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir pandas==3.0.5 python-dateutil==2.9.0.post0

# Visible fixture data (the "live system"). The agent/oracle consumes this.
COPY files/ /app/data/
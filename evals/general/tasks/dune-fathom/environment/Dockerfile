FROM bench-base:python-3.12

WORKDIR /app

# API stack used by the service and the verifier.
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Fixtures and provided tooling (the "fathom services repo").
COPY files/ /app/

# The agent must never find tests/ or solution/ inside the image.
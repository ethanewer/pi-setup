FROM bench-base:python-3.12

# Granite Grove office-automation task: calendar fetch, overlap finder, transfer rule.
RUN pip install --no-cache-dir python-dateutil ics >/dev/null 2>&1 && \
    python3 -c "import dateutil, ics" 

WORKDIR /app

COPY files/ /app/

# Provided toolchain (driven by the agent's pipeline, never modified by verifier).
RUN chmod +x /app/tools/*.py

ENV PYTHONUNBUFFERED=1
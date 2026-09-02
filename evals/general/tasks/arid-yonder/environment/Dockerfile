FROM bench-base:python-3.12

WORKDIR /app

# pandas installed per environment spec (not strictly required by the task)
RUN pip install --no-cache-dir pandas

# shipped read-only fixtures the agent must parse
COPY files/data /app/data

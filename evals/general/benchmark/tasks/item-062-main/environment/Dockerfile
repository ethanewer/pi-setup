FROM bench-base:python-3.12

WORKDIR /app

# Deterministically build the Open-English-Wordnet-style database.
COPY files/generate_wn.py /app/generate_wn.py
RUN python3 /app/generate_wn.py /app/wn.db && rm /app/generate_wn.py

# The agent's tooling of choice (sqlite3 CLI + python sqlite3) is present.
RUN which python3 sqlite3 || true
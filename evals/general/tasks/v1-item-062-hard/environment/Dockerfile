FROM bench-base:python-3.12

WORKDIR /app

# Deterministically build a LARGE Open-English-Wordnet-style database
# (120k synsets / 200k words / ~400k senses / ~600k relations) with NO indexes.
COPY files/generate_wn.py /app/generate_wn.py
RUN python3 /app/generate_wn.py /app/wn.db 120000 200000 && rm /app/generate_wn.py
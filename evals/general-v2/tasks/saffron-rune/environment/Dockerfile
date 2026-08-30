FROM bench-base:python-3.12

WORKDIR /app

# numpy for the fixed-size feature arrays; everything else is stdlib.
RUN python3 -m pip install --no-cache-dir --quiet numpy==2.1.3

# Read-only fixture: the molecule catalog (id,smiles CSV, incl. invalid rows).
COPY files/ /app/

CMD ["/bin/bash"]

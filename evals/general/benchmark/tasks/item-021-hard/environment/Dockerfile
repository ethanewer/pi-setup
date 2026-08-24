FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir biopython>=1.81

COPY files/plasmid.fa /app/plasmid.fa
COPY files/edit.txt /app/edit.txt
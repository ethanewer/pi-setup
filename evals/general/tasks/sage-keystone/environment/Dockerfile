FROM bench-base:python-3.12

WORKDIR /app

# Libraries used for the three jobs: fillable-form field inspection (pypdf),
# SPARQL evaluation on the RDF ledger (rdflib), and skinned-mesh array decode
# (numpy). Pinned so the parses the resolver performs at verify time match the
# fixtures generated with these exact versions.
RUN pip install --no-cache-dir \
        pypdf==6.16.2 \
        rdflib==7.6.0 \
        numpy==2.5.2

# Fresh workspace fixtures. The agent writes its deliverables into /app.
COPY files/ /app/
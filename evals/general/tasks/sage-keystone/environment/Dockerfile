FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
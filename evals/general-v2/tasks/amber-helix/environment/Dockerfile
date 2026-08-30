FROM bench-base:python-3.12

WORKDIR /app

# Numeric/ML stack used by the affinity-tuning pipeline and (optionally) the
# sequence tooling. Kept CPU-only; installs finish well inside the build budget.
RUN pip install --no-cache-dir \
        numpy \
        scipy \
        pandas \
        scikit-learn \
        biopython

# Task fixtures: molecular catalog + wanted-names list, the mutagenesis target
# FASTA and scene, and the binding-affinity descriptor/measurement matrices.
# The Python deliverables are authored by the agent in /app, not shipped here.
COPY files/ /app/

# Data produces by the oracle/solver at run time (mount is not required for
# these; they land under /app which is the verifier's mount point too).
RUN mkdir -p /app
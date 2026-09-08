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

# Numeric/ML stack used by the affinity-tuning pipeline and (optionally) the
# sequence tooling. Kept CPU-only; installs finish well inside the build budget.
RUN pip install --no-cache-dir \
        numpy==2.5.3 \
        scipy==1.18.1 \
        pandas==3.0.5 \
        scikit-learn==1.9.0 \
        biopython==1.88

# Task fixtures: molecular catalog + wanted-names list, the mutagenesis target
# FASTA and scene, and the binding-affinity descriptor/measurement matrices.
# The Python deliverables are authored by the agent in /app, not shipped here.
COPY files/ /app/

# Data produces by the oracle/solver at run time (mount is not required for
# these; they land under /app which is the verifier's mount point too).
RUN mkdir -p /app
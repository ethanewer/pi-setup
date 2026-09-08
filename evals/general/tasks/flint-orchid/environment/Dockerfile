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

# Raw heterogeneous fixtures: a fillable AcroForm PDF, an HTML financial
# report, an RDF/Turtle relationship catalog, and a custom skinned-mesh binary.
COPY files/ /app/

RUN pip install --no-cache-dir --quiet pypdf==6.18.0 beautifulsoup4==4.15.0 rdflib==7.6.0 numpy==2.5.3

RUN python3 - <<'PY'
import pypdf, bs4, rdflib, numpy
print('pypdf', pypdf.__version__, '| bs4', bs4.__version__,
      '| rdflib', rdflib.__version__, '| numpy', numpy.__version__)
PY

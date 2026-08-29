FROM bench-base:python-3.12
WORKDIR /app

# Raw heterogeneous fixtures: a fillable AcroForm PDF, an HTML financial
# report, an RDF/Turtle relationship catalog, and a custom skinned-mesh binary.
COPY files/ /app/

RUN pip install --no-cache-dir --quiet pypdf beautifulsoup4 rdflib numpy

RUN python3 - <<'PY'
import pypdf, bs4, rdflib, numpy
print('pypdf', pypdf.__version__, '| bs4', bs4.__version__,
      '| rdflib', rdflib.__version__, '| numpy', numpy.__version__)
PY

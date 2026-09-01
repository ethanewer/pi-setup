FROM bench-base:python-3.12

WORKDIR /app

# Exact-optimization stack (scipy ships scipy.optimize.milp backed by HiGHS).
RUN pip install --quiet --no-cache-dir --no-warn-script-location scipy==1.13.1

# Visible weighted Max-SAT instance (read-only fixture).
COPY files/ /app/instances/
RUN chmod -R a-w /app/instances

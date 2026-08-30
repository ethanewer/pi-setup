FROM bench-base:python-3.12

WORKDIR /app

# Numeric/ML stack for the yield-rank modelling pipeline. CPU-only; installs
# finish well inside the build budget.
RUN pip install --no-cache-dir \
        numpy \
        scipy \
        pandas \
        scikit-learn

# Task fixtures: the process-sensor feature matrix and the matching measured
# wafer-yield vector. The deliverable program is authored by the agent in /app,
# not shipped here.
COPY files/ /app/

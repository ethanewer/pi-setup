FROM bench-base:python-3.12

WORKDIR /app

# Data-wrangling toolchain for the quartz-helix data-mart close-out.
RUN pip install --no-cache-dir --quiet pandas numpy

# Shipped workbench fixtures (same schema as the hidden cases) so the agent
# can develop and self-test the transforms locally.
COPY files/ /app/

WORKDIR /app

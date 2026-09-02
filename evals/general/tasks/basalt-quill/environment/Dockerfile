FROM bench-base:python-3.12
WORKDIR /app

# scientific python stack for spectra fitting + astropy compound models
RUN pip install --no-cache-dir numpy scipy astropy sympy

# R runtime for the adaptive-rejection-sampling component
RUN apt-get update \
 && apt-get install -y --no-install-recommends r-base \
 && rm -rf /var/lib/apt/lists/*

# fixtures the agent works from
COPY files/ /app/
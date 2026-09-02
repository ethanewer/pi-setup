FROM bench-base:python-3.12

WORKDIR /app

# Task tooling (not the fix). Kept offline-friendly.
RUN python -m pip install --no-cache-dir "pytest>=7" "setuptools>=61" wheel ipython

COPY files/ /app/

WORKDIR /app
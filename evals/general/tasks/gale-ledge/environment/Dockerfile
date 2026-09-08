FROM bench-base:python-3.12

WORKDIR /app

# Task tooling (not the fix). Kept offline-friendly.
RUN python -m pip install --no-cache-dir "pytest>=7" "setuptools>=61" wheel==0.48.0 ipython==9.17.1

COPY files/ /app/

WORKDIR /app
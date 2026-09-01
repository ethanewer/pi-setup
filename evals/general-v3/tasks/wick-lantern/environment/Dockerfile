FROM bench-base:python-3.12

WORKDIR /app

# Jupyter Server toolchain for the Wick Lantern lightroom notebook.
RUN pip install --quiet --no-cache-dir "notebook"

# Visible notes for local smoke-testing only; NOT graded by the verifier.
COPY files/ /app/

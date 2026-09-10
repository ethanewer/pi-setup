FROM bench-base:python-3.12

# pytest for the pipeline's test steps (pinned per suite policy).
RUN pip install --no-cache-dir pytest==9.1.1

WORKDIR /app

COPY files/ /app/

# The fixture repository (with its git history) is generated at build time by
# the script below; the generator itself is not part of the shipped task.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && python3 /app/gen_repo.py /app \
 && rm -f /app/gen_repo.py
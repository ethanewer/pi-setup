FROM bench-base:python-3.12
WORKDIR /app
COPY files/ /app/
RUN chmod +x /app/bin/observe /app/bin/sim-gates \
 && pip install --no-cache-dir numpy
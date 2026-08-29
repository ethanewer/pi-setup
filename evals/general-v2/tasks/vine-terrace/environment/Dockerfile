FROM bench-base:python-3.12
WORKDIR /app
# pin to versions the task was validated against
RUN pip install --no-cache-dir \
      numpy==2.5.2 \
      networkx==3.6.1 \
      jax==0.11.1 \
      jaxlib==0.11.1 \
      jaxley==0.13.0 \
      pytest==9.1.1
COPY files/ /app/

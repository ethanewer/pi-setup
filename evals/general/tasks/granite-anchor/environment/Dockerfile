FROM bench-base:python-3.12

WORKDIR /app

# Reified for the env manifest (numpy available but not required by the task).
RUN pip install --no-cache-dir numpy

COPY files/ /app/

CMD ["/bin/bash"]
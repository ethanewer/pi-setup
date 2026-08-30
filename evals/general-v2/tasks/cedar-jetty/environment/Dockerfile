FROM bench-base:python-3.12
WORKDIR /app
RUN pip install --no-cache-dir numpy scipy sympy
# No fixtures are pre-placed: every deliverable (/app/kernels.py, /app/out.npy)
# is produced by the agent during the task run.
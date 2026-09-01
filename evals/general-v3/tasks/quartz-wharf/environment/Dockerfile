FROM bench-base:python-3.12

RUN python3 -m pip install --no-cache-dir numpy scipy

WORKDIR /app

# All working files are created by the agent during the session
# (/app/integrate.py, /app/eig.py, /app/bench.py). Nothing is baked in here.
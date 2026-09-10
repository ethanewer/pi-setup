FROM bench-base:python-3.12
WORKDIR /app
COPY files/ /app/
RUN python3 /app/_build_sym.py && rm -f /app/_build_sym.py /app/_lib.py
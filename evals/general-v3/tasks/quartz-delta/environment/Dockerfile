FROM bench-base:python-3.12

# Quartz-delta numerical-kernels task. numpy / scipy / sympy provide the
# linear-programming and linear-algebra primitives the kernel library builds on.
RUN pip install --no-cache-dir numpy scipy sympy

WORKDIR /app

COPY files/ /app/
FROM bench-base:python-3.12

WORKDIR /app

# Only a README touchstone; the agent writes the stdin/stdout program itself.
RUN printf 'write /app/transform.py\n' > /app/README.txt
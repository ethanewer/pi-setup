FROM bench-base:python-3.12

# numpy only: value iteration / linear solve on the grader side.
RUN pip install --no-cache-dir --disable-pip-version-check numpy

WORKDIR /app

COPY files/ /app/

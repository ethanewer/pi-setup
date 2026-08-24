FROM bench-base:python-3.12

WORKDIR /app

RUN pip install numpy scipy

COPY files/ /app/
RUN mkdir -p /app/out
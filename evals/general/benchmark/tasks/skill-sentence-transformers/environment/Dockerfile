FROM bench-base:python-3.12

WORKDIR /app

# sentence-transformers + torch CPU wheels, CA-configured by the bench base image
RUN pip install --no-cache-dir sentence-transformers==3.0.1

COPY files/ /app/
RUN chmod -R u+rX /app
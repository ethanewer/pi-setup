FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check cryptography

COPY files/public.pem /app/certificate.pem
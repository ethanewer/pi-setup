FROM bench-base:python-3.12

WORKDIR /app

# Tabular ML: pandas + scikit-learn. Installs from PyPI through the corporate
# CA proxy baked into bench-base.
RUN pip install --no-cache-dir --quiet \
        numpy \
        pandas \
        scikit-learn

COPY files/ /app/

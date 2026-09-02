FROM bench-base:python-3.12

WORKDIR /app

# Spreadsheet writing/reading (openpyxl) and dataframe convenience (pandas)
# that the /app/solve.py pipeline and the verifier rely on.
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        openpyxl \
        pandas

# The committed fleet-request input the solver runs against.
RUN mkdir -p /opt/keystone
COPY files/requests.csv /opt/keystone/requests.csv

# Sanity checks that the toolchain is present before the agent starts.
RUN python3 -c "import openpyxl, pandas; print('openpyxl', openpyxl.__version__)"
RUN python3 -c "import os; assert os.path.isfile('/opt/keystone/requests.csv')"
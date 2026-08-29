FROM bench-base:python-3.12
WORKDIR /app
COPY files/vault_server.py /app/vault_server.py
COPY files/vault_fixtures.json /app/vault_fixtures.json
CMD ["python3", "-c", "print('basalt-vault ready')"]
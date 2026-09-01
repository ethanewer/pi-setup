FROM bench-base:python-3.12

WORKDIR /app

# A cookie value that contains raw CRLF bytes, as a web attacker might submit to
# perform a response-splitting / header-injection attack.
RUN python3 - <<'PY'
open('/app/threat.txt','wb').write(b"session=alice\r\nSet-Cookie: admin=true")
PY
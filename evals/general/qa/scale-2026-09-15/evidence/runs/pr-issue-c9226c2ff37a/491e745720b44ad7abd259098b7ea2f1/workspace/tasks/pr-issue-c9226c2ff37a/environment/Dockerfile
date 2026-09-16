FROM bench-base:python-3.12
WORKDIR /app
RUN python -m pip install --no-cache-dir \
    anyio==4.6.2.post1 certifi==2024.8.30 \
    httpcore==1.0.6 idna==3.10 pytest==8.3.3
RUN python - <<'PY'
import io, tarfile, urllib.request
import hashlib
url = "https://github.com/encode/httpx/archive/6f9b50990dad9645a6f9dc0e1eb90af0a6474c3b.tar.gz"
with urllib.request.urlopen(url) as response:
    data = response.read()
expected = "9197128b446cf7dd9c116b90d58ec037a8a0e8bdfe508f271eb0486e63c35761"
if hashlib.sha256(data).hexdigest() != expected:
    raise SystemExit("unexpected source archive digest")
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
    root = archive.getmembers()[0].name.split("/")[0]
    archive.extractall("/tmp/httpx-src")
PY
RUN mv /tmp/httpx-src/httpx-6f9b50990dad9645a6f9dc0e1eb90af0a6474c3b/* /app/ && rm -rf /tmp/httpx-src

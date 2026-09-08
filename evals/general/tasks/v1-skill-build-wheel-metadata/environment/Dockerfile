FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir --upgrade pip==26.2.1 setuptools==84.0.0 wheel==0.48.0

RUN mkdir -p /app/melonpkg/pkg && \
    printf 'def add(a, b):\n    return a + b\n' > /app/melonpkg/pkg/core.py && \
    printf 'from .core import add\n' > /app/melonpkg/pkg/__init__.py && \
    printf '# TODO: fill in the real pyproject.toml (see instruction.md)\n' > /app/melonpkg/pyproject.toml
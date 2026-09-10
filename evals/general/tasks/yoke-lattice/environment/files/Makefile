PY ?= python3

all: lint test dist

lint:
	$(PY) -m yoke lint README.md pyproject.toml yoke tests samples .gitignore

test:
	$(PY) -m pytest -q tests

dist:
	$(PY) -m yoke build

.PHONY: all lint test dist
PY ?= python3

.PHONY: test smoke

test:
	$(PY) -m unittest discover -s tests -t . -q

smoke: test
	$(PY) -m enrichd process --input workloads/visible.jsonl --output /tmp/enrichd.smoke.jsonl
	wc -l workloads/visible.jsonl /tmp/enrichd.smoke.jsonl
	rm -f /tmp/enrichd.smoke.jsonl

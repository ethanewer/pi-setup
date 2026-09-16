#!/usr/bin/env python3
import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("triage", "/app/triage.py")
assert spec and spec.loader
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)
report = triage.build_report(Path("/app/source/events.jsonl").read_text(encoding="utf-8").splitlines())
assert "Records: 4" in report
assert "Levels: CRITICAL=1, ERROR=1, WARNING=1, INFO=1, DEBUG=0" in report
assert "Components: worker=2, api=1, db=1" in report
assert '[2026-01-02T08:59:59Z] ERROR api: bad [request] "quoted"' in report
assert "[2026-01-02T09:00:02Z] INFO worker: ready [literal]" in report
assert "retry\\path" in report
print("REPRO_OK")

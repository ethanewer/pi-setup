# Legacy v3.0-era scripts and report

Superseded, kept for provenance. Nothing here is used by a current publish; the live
recipes are one directory up and the live collector is `tools/collect_task_records.py`.

These date from 2026-09-02/03, when the suite was 765 tasks and verifiers still awarded
partial credit. `REPORT.md` is the results record from that run, with fractional scores
like 0.830 (635.05 / 765). Every reward in it was later binarized under the rule
`new = 1 iff old >= 1.0`, the suite grew to 785 tasks, and two tasks were retired, so none
of its numbers are comparable to a current version. It is kept because it is the only
record of the pre-binarization scores and of what the suite looked like before the v3.4
defect sweep.

## Why the three rename/scrub scripts matter

`rename_tasks.py`, `rename_pass2.py` and `scrub_markers.py` are how 23 tasks got opaque
two-word identifiers and had their provenance markers rewritten, byte-preserving, using
`git mv` so history survived. That is part of the independence story: the audit in
`tools/audit_independence_stream.py` compares task content against a frozen
terminal-bench checkout, and task names and embedded markers are exactly where an
origin would leak. `scrub_markers.py` reads its mapping from `/tmp/origmap.txt`, which is
not committed and no longer exists, so the original-name mapping is deliberately
unrecoverable from this repository.

## The rest

| File | What it was |
|---|---|
| `to_hub.py` | Normalized traces into the v3.0 HF layout. Superseded by `tools/collect_task_records.py`. |
| `upload_hub.py` | Uploaded `hub/v3.0` with `huggingface_hub`. Superseded by `tools/publish_version.sh`, which validates the tree is complete and binary before uploading and verifies against the Hub afterward. |
| `summarize.py` | Reward, pass rate and exception summary over a harbor job directory. Still works; `tools/check_agent_actually_ran.py` now covers the part that matters, which is whether a trial measured anything at all. |

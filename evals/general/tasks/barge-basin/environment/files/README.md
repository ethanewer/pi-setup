# barge-basin environment files

Deliberately empty on purpose: the agent must author its own reproduction of
the bug it is asked to fix. The reproduction is the task deliverable
`/app/repro.py` (see ../instruction.md). Upstream source is cloned by
environment/Dockerfile at the pinned parent commit; no probe files ship here
so nothing leaks the trigger input.
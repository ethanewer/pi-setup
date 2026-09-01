# Fab-scheduling feasibility

`/app/fab_jobs.json` describes two jobs in a semiconductor fabrication (fab) shop, where a job is a sequence of processing steps. Each step names a machine and how many time units it occupies. A workstation (machine) processes one job at a time, and **a job may revisit the same machine at a later step** (re-entrant flow), which is typical of fab scheduling.

```json
{
  "a": [{"machine": "M1", "duration": 3}, {"machine": "M2", "duration": 2}, {"machine": "M1", "duration": 4}],
  "b": [{"machine": "M2", "duration": 2}, {"machine": "M1", "duration": 2}, {"machine": "M2", "duration": 3}]
}
```

So job `a` needs `M1` for 3, then `M2` for 2, then `M1` again for 4; job `b` needs `M2` for 2, then `M1` for 2, then `M2` for 3.

## Your task

Produce any **feasible** schedule (a valid assignment of a start time `start >= 0` to every step of both jobs) and write it to `/app/schedule.json`. Use this exact shape:

```json
{
  "a": [{"step": 0, "start": 0}, {"step": 1, "start": 3}, {"step": 2, "start": 6}],
  "b": [{"step": 0, "start": 10}, {"step": 1, "start": 12}, {"step": 2, "start": 14}]
}
```

(the start values above are just an example—choose values that make the schedule feasible).

A schedule is feasible iff every requirement holds:

1. Every operation has `start >= 0`.
2. For each job, its steps run in order: `start[i] + duration[i] <= start[i+1]` for all consecutive steps.
3. On any given machine, no two operations overlap: for every pair of operations assigned to the same machine, either one ends before the other starts (`start1 + duration1 <= start2` or `start2 + duration2 <= start1`).

Find the exact start-times in the `start` field for each step so the schedule passes the feasibility check.
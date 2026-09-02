# Queue scheduling simulation (FIFO)

`/app/jobs.txt` describes a set of discrete jobs submitted to a **single CPU/queue**. Each line is tab-separated: `<job_id> <arrival_time> <processing_time>`. All times are integer time units.

The scheduler is **FIFO (first-in, first-out)**: jobs are processed in order of **increasing arrival time**; when two jobs arrive at the same time, the one that appears **earlier in the file** is processed first. A job can start only after it has arrived **and** the CPU has finished the previous job.

For each job compute:
- its **start time** = `max(completion of previous job, arrival time)`
- its **waiting time** = `start time - arrival time`
- its **completion time** = `start time + processing time`

Write `/app/queue.json` as a JSON object with exactly these keys:
- `"jobs"`: total number of jobs (integer)
- `"avg_wait"`: mean waiting time over all jobs (float, rounded to 2 decimals)
- `"completion_time"`: completion time of the last job processed (integer)

The values are deterministic. Write the scheduler as `/app/schedule.py` and run it so `/app/queue.json` is produced.
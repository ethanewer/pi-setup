#!/usr/bin/env python3
"""Collect oracle results from a harbor job directory into specs.

Writes:
  specs/oracle_report.json   per-task reward + errors (verification record)
  specs/oracle_times.json    per-task oracle wall time + reward
                             (feeds tools/build_difficulty.py)

Usage: python3 tools/collect_oracle_results.py JOB_DIR [JOB_NAME]
JOB_DIR is the -o output dir; if JOB_NAME omitted, search all subjobs.
"""
import datetime, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    if len(sys.argv) < 2:
        print('usage: collect_oracle_results.py JOB_DIR [JOB_NAME]')
        return 2
    job_dir = Path(sys.argv[1])
    if not job_dir.exists():
        print(f'ERROR {job_dir} missing')
        return 1
    roots = ([job_dir / sys.argv[2]] if len(sys.argv) > 2
             else [p for p in job_dir.iterdir() if p.is_dir()])
    report, times, problems = {}, {}, []
    n_trials = 0
    for root in roots:
        for trial in sorted(root.glob('*/result.json')):
            try:
                data = json.loads(trial.read_text())
            except Exception:
                continue
            task = data.get('task_name')
            if not task:
                continue
            n_trials += 1
            rp = trial.parent / 'verifier/reward.txt'
            reward = None
            if rp.exists():
                try:
                    reward = float(rp.read_text().strip())
                except ValueError:
                    pass
            duration = None
            try:
                s = data.get('started_at')
                f = data.get('finished_at')
                if s and f:
                    fmt = lambda x: datetime.datetime.fromisoformat(x)
                    duration = round((fmt(f) - fmt(s)).total_seconds(), 1)
            except Exception:
                pass
            errored = bool(data.get('error'))
            report[task] = {'reward': reward, 'errored': errored,
                            'trial': trial.parent.name}
            times[task] = {'oracle_time_sec': duration, 'reward': reward}
            if errored:
                problems.append(f'{task}: trial errored')
            elif reward != 1.0:
                problems.append(f'{task}: oracle reward {reward}')
    (ROOT / 'specs/oracle_report.json').write_text(
        json.dumps({'collected_at':
                    datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    'job_dir': str(job_dir), 'trials': n_trials,
                    'tasks': report}, indent=2) + '\n')
    (ROOT / 'specs/oracle_times.json').write_text(
        json.dumps(times, indent=2) + '\n')
    print(f'trials={n_trials} tasks={len(report)} problems={len(problems)}')
    for p in problems:
        print('ERROR', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())

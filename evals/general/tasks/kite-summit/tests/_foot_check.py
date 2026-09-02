#!/usr/bin/env python3
"""Independent footprint check for /app/footprint_report.txt.

Re-measures the global site-packages tree itself, recomputes the limit from the
pristine baseline, and requires that the report's measured_bytes equals the real
current size (so the report cannot be faked) and that the real size stays within
the bound with within_budget=true.

Exit 0 only when all hold. Prints details to stdout.
"""
import os
import site
import sys


def site_packages_size():
    d = site.getsitepackages()[0]
    n = 0
    for r, _, fs in os.walk(d):
        for f in fs:
            try:
                n += os.path.getsize(os.path.join(r, f))
            except OSError:
                pass
    return n


def main():
    report = '/app/footprint_report.txt'
    problems = []
    if not os.path.exists(report):
        print('FAIL: /app/footprint_report.txt missing')
        return 1
    try:
        baseline = int(open('/opt/site-baseline.txt').read().strip())
    except Exception as e:  # noqa: BLE001
        print(f'FAIL: cannot read baseline: {e!r}')
        return 1
    current = site_packages_size()
    limit = int(round(baseline * 1.08)) + 12 * 1024 * 1024

    kv = {}
    with open(report) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            if ':' in line:
                k, v = line.split(':', 1)
                kv[k.strip()] = v.strip()
    for key in ('baseline_bytes', 'measured_bytes', 'limit_bytes', 'within_budget'):
        if key not in kv:
            problems.append(f'report missing key {key}')
    if not problems:
        try:
            r_base, r_meas, r_lim = (int(kv['baseline_bytes']),
                                     int(kv['measured_bytes']),
                                     int(kv['limit_bytes']))
            if r_base != baseline:
                problems.append(f'report baseline {r_base} != real {baseline}')
            if r_lim != limit:
                problems.append(f'report limit {r_lim} != computed {limit}')
            if r_meas != current:
                problems.append(f'report measured {r_meas} != re-measured {current}')
            if kv['within_budget'].lower() != 'true':
                problems.append('report within_budget is not true')
        except ValueError as e:
            problems.append(f'unparseable report numbers: {e!r}')
    if current > limit:
        problems.append(f'real site-packages {current} > limit {limit}')
    print(f'footprint: baseline={baseline} current={current} limit={limit}')
    for p in problems:
        print(f'FAIL: {p}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())

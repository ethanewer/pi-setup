#!/usr/bin/env python3
"""Shared, fail-closed QA entry point for every new authoring pipeline."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

from author_task import fingerprint, validate
import _toml_compat

ROOT = Path(__file__).resolve().parents[1]
REVIEW_GATES = ('source', 'behavior', 'isolation', 'negative_controls',
                'reproducibility', 'contamination', 'difficulty', 'diversity')


def review_errors(review, digest, author):
    errors = []
    if not isinstance(review, dict) or review.get('fingerprint') != digest:
        return ['missing or stale review fingerprint']
    for gate in REVIEW_GATES:
        record = review.get(gate, {})
        if not isinstance(record, dict) or record.get('status') != 'pass' or not record.get('evidence') or not record.get('reviewer') or record.get('reviewer') == author:
            errors.append(f'{gate}: requires pass, evidence, and a reviewer other than author')
    return errors


def run_controls(task, output):
    errors = []
    for agent, want in (('oracle', '1'), ('nop', '0')):
        job = output / agent
        with (output / f'{agent}.log').open('w') as log:
            try:
                result = subprocess.run(['harbor', 'run', '-p', str(task), '-a', agent,
                    '-k', '1', '-n', '1', '-y', '-q', '--job-name', agent, '-o', str(job)],
                    stdout=log, stderr=subprocess.STDOUT, timeout=3000)
                rewards = list(job.rglob('reward.txt'))
                if result.returncode != 0 or len(rewards) != 1 or rewards[0].read_text().strip() not in (want, want + '.0'):
                    errors.append(f'{agent}: failed command or unexpected/missing reward')
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f'{agent}: {exc}')
    return errors


def run_docker_controls(task, output):
    """Enforce offline controls when the installed harness cannot disable networking."""
    config = _toml_compat.loads((task / 'task.toml').read_text())
    environment = config.get('environment', {})
    if environment.get('network_mode') != 'no-network':
        return ['direct Docker controls require explicit network_mode=no-network']
    image = 'general-qa-' + uuid.uuid4().hex
    owner = os.environ.get('GENERAL_QA_RUN_ID')
    labels = ['--label', 'general.factory=' + owner] if owner else []
    errors = []
    try:
        with (output / 'build.log').open('w') as log:
            built = subprocess.run(['docker', 'build', *labels, '-t', image, str(task / 'environment')],
                                   stdout=log, stderr=subprocess.STDOUT,
                                   timeout=environment.get('build_timeout_sec', 600))
        if built.returncode:
            return ['Docker image build failed; see build.log']
        identity = subprocess.check_output(['docker', 'image', 'inspect', image,
                                            '--format', '{{.Id}}'], text=True).strip()
        (output / 'environment.json').write_text(json.dumps({
            'image_id': identity, 'network': 'none',
            'cpus': environment.get('cpus', 1),
            'memory_mb': environment.get('memory_mb', 4096),
            'build_timeout_sec': environment.get('build_timeout_sec', 600),
            'verifier_timeout_sec': config.get('verifier', {}).get('timeout_sec', 300),
            'agent_timeout_sec': config.get('agent', {}).get('timeout_sec', 900)}, indent=2) + '\n')
        for agent, want in (('oracle', '1'), ('nop', '0')):
            job = output / agent
            job.mkdir()
            name = 'general-qa-' + uuid.uuid4().hex
            command = ['docker', 'run', *labels, '--name', name, '--network', 'none',
                       '--cpus', str(environment.get('cpus', 1)),
                       '--memory', f'{environment.get("memory_mb", 4096)}m',
                       '--mount', f'type=bind,source={(task / "tests").resolve()},target=/tests,readonly',
                       '--mount', f'type=bind,source={job.resolve()},target=/logs/verifier']
            if agent == 'oracle':
                command += ['--mount', f'type=bind,source={(task / "solution").resolve()},target=/solution,readonly']
            script = ('/solution/solve.sh && /tests/test.sh' if agent == 'oracle'
                      else '/tests/test.sh; test -f /logs/verifier/reward.txt')
            command += [image, '/bin/bash', '-c', script]
            budget = config.get('verifier', {}).get('timeout_sec', 300)
            if agent == 'oracle':
                budget += config.get('agent', {}).get('timeout_sec', 900)
            started = time.monotonic()
            try:
                with (output / f'{agent}.log').open('w') as log:
                    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=budget)
                rewards = list(job.rglob('reward.txt'))
                reward = rewards[0].read_text().strip() if len(rewards) == 1 else None
                (output / f'{agent}-result.json').write_text(json.dumps({
                    'agent': agent, 'elapsed_seconds': time.monotonic() - started,
                    'returncode': result.returncode, 'reward': reward,
                    'expected_reward': want}, indent=2) + '\n')
                if result.returncode or reward not in (want, want + '.0'):
                    errors.append(f'{agent}: failed command or unexpected/missing reward')
            except (OSError, subprocess.TimeoutExpired) as exc:
                errors.append(f'{agent}: {exc}')
            finally:
                subprocess.run(['docker', 'rm', '--force', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        errors.append(f'Docker controls: {exc}')
    finally:
        subprocess.run(['docker', 'image', 'rm', image], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--review', type=Path)
    parser.add_argument('--suite-root', type=Path, default=ROOT)
    parser.add_argument('--runtime-backend', choices=('harbor', 'docker'), default='harbor')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--static-only', action='store_true', help='draft check; never an acceptance result')
    mode.add_argument('--runtime-only', action='store_true', help='static and runtime controls before review; never acceptance')
    parser.add_argument('--output-root', type=Path, default=ROOT / 'qa/results')
    args = parser.parse_args()
    try:
        candidate = validate(json.loads(args.candidate.read_text()))
        task = args.suite_root.resolve() / 'tasks' / candidate['task_id']
        if not task.is_dir() or task.is_symlink():
            raise ValueError('task directory missing or symlinked')
        digest = fingerprint(task, candidate)
        args.output_root.mkdir(parents=True, exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix=candidate['task_id'] + '-', dir=args.output_root))
        errors = []
        controls = run_docker_controls if args.runtime_backend == 'docker' else run_controls
        for tool in ('lint_tasks.py', 'check_binary_reward.py'):
            with (output / (tool + '.log')).open('w') as log:
                result = subprocess.run([sys.executable, str(ROOT / 'tools' / tool), '--root', str(args.suite_root.resolve()), '--task', task.name], stdout=log, stderr=subprocess.STDOUT)
            if result.returncode:
                errors.append(f'{tool}: failed (see log)')
        if args.runtime_only:
            if not errors:
                errors.extend(controls(task, output))
        elif not args.static_only:
            review = json.loads(args.review.read_text()) if args.review else {}
            errors.extend(review_errors(review, digest, candidate['author']))
            if not errors:
                errors.extend(controls(task, output))
        if fingerprint(task, candidate) != digest:
            errors.append('task changed during QA')
        report = {'task_id': task.name, 'fingerprint': digest,
                  'status': 'failed' if errors else ('draft' if args.static_only or args.runtime_only else 'accepted'),
                  'mode': 'static' if args.static_only else ('runtime' if args.runtime_only else 'acceptance'),
                  'runtime_backend': args.runtime_backend,
                  'errors': errors}
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
        print(f'Evidence: {output}')
        return 1 if errors else 0
    except (ValueError, OSError, TypeError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

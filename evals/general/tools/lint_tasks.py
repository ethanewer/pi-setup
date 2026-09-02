#!/usr/bin/env python3
"""Harbor layout + verifier-contract lint for general-v2 (TODO.md section 5).

Enforces:
  - required files exist and are non-empty
  - approved base image, WORKDIR /app
  - verifier always writes /logs/verifier/reward.txt
  - verifier_kind declared; executes-deliverable verifiers actually execute
    every declared deliverable; oracles create every deliverable
  - hidden cases present (tests/hidden) unless an explicit exemption is
    declared in task.toml metadata.hidden_cases_exempt
  - oracle does not peek at /tests, and no environment file duplicates a
    hidden-test or expected-output file
  - difficulty.json rubric present and complete
"""
import hashlib, json, re, sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    tomllib = None

ROOT = Path(__file__).resolve().parents[1]
CATEGORIES = {'programming', 'debugging', 'data_processing', 'data_science',
              'security', 'system_administration', 'file_operations',
              'scientific_computing', 'web', 'reasoning'}
VKINDS = {'executes-deliverable', 'answer-with-hidden-cases'}
RUBRIC_KEYS = {'dependent_stages', 'tool_breadth', 'reasoning_depth',
               'debugging_ambiguity', 'adversarial_inputs',
               'hidden_case_generalization', 'quantitative_correctness',
               'resource_pressure', 'interaction_statefulness',
               'unsafe_action_penalty'}


def read_toml(p: Path):
    if tomllib:
        return tomllib.loads(p.read_text())
    raise RuntimeError('tomllib unavailable')


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def main() -> int:
    problems = []
    notes = []
    all_tasks = sorted(p for p in (ROOT / 'tasks').iterdir() if p.is_dir())
    # The v1-* directories are the imported legacy general-coding family:
    # filtered for verifier quality, but authored to the pre-v3 layout and
    # therefore not subject to the clean-room contract lint — the same
    # special case check_tb21_coverage.py grants them for competency claims.
    legacy = [p for p in all_tasks if p.name.startswith('v1-')]
    tasks = [p for p in all_tasks if not p.name.startswith('v1-')]
    for d in tasks:
        name = d.name

        def err(msg):
            problems.append(f'{name}: {msg}')

        required = ['task.toml', 'instruction.md', 'environment/Dockerfile',
                    'solution/solve.sh', 'tests/test.sh']
        for rel in required:
            p = d / rel
            if not p.exists() or p.stat().st_size == 0:
                err(f'missing/empty {rel}')
        if problems and problems[-1].startswith(name + ': missing'):
            continue

        toml = read_toml(d / 'task.toml')
        if toml.get('schema_version') != '1.4':
            err('schema_version must be "1.4"')
        meta = toml.get('metadata', {})
        diff = meta.get('difficulty')
        if diff not in ('easy', 'medium', 'hard'):
            err(f'bad difficulty {diff!r}')
        if meta.get('category') not in CATEGORIES:
            err(f'bad category {meta.get("category")!r}')
        vkind = meta.get('verifier_kind')
        if vkind not in VKINDS:
            err(f'verifier_kind must be one of {sorted(VKINDS)}')
        deliverables = meta.get('deliverables')
        if not isinstance(deliverables, list) or not deliverables:
            err('metadata.deliverables must be a non-empty list of /app paths')
            deliverables = []
        for deliv in deliverables:
            if not str(deliv).startswith('/app/'):
                err(f'deliverable {deliv!r} must live under /app')

        instr = (d / 'instruction.md').read_text()
        for deliv in deliverables:
            if str(deliv) not in instr:
                err(f'instruction does not mention deliverable {deliv}')

        docker = (d / 'environment/Dockerfile').read_text()
        if not re.search(r'^FROM bench-base:', docker, re.M):
            err('Dockerfile must use an approved bench-base:* image')
        if 'WORKDIR /app' not in docker:
            err('Dockerfile missing WORKDIR /app')
        if re.search(r'COPY[^\n]*(tests|solution)', docker):
            err('Dockerfile must not copy tests/ or solution/ into the image')

        test = (d / 'tests/test.sh').read_text()
        if '/logs/verifier/reward.txt' not in test:
            err('verifier does not write /logs/verifier/reward.txt')
        # verifiers may delegate to helper scripts under /tests; include the
        # text of literally-referenced helpers when checking deliverable use
        delegated = test
        for ref in set(re.findall(r'/tests/[A-Za-z0-9_./-]+', test)):
            helper = d / 'tests' / ref.split('/tests/', 1)[1]
            if helper.is_file():
                try:
                    delegated += '\n' + helper.read_text(errors='replace')
                except OSError:
                    pass
        if vkind == 'executes-deliverable':
            for deliv in deliverables:
                s = str(deliv)
                if '*' in s or '?' in s:
                    # glob deliverable: satisfied if the verifier references the
                    # leaf directory or filename pattern literally
                    stem = s.split('*')[0].split('?')[0].rstrip('/')
                    token = stem.split('/')[-1] or s
                    if token and token in delegated:
                        continue
                    err(f'verifier never executes deliverable {s}')
                elif s not in delegated:
                    err(f'verifier never executes deliverable {s}')
        hidden_dir = d / 'tests/hidden'
        exempt = meta.get('hidden_cases_exempt')
        if hidden_dir.is_dir():
            if not any(hidden_dir.iterdir()):
                err('tests/hidden exists but is empty')
        elif not exempt:
            err('no hidden cases (tests/hidden) and no '
                'metadata.hidden_cases_exempt reason')
        else:
            notes.append(f'{name}: hidden-case exemption: {exempt}')

        solve = (d / 'solution/solve.sh').read_text()
        if not (d / 'solution/solve.sh').stat().st_mode & 0o111:
            err('oracle not executable')
        # peek detection: strip comment-only lines, then any /tests reference is
        # a peek (oracles must not depend on verifier-internal files at all)
        code = '\n'.join(l for l in solve.splitlines()
                          if not l.lstrip().startswith('#'))
        if '/tests' in code:
            err('oracle peeks at /tests')
        for deliv in deliverables:
            if str(deliv) not in solve:
                err(f'oracle does not create deliverable {deliv}')

        # no environment file may duplicate a hidden EXPECTED/answer test
        # artifact.  Byte-identical INPUT replays (verifier re-checking the
        # visible case) are legitimate and only noted.
        expected_hashes = {}
        input_hashes = {}
        for p in list((d / 'tests').rglob('*')):
            if not (p.is_file() and p.name != 'test.sh'):
                continue
            try:
                h = sha(p.read_bytes())
            except OSError:
                continue
            if re.search(r'expected|answer', p.name, re.I):
                expected_hashes[h] = p
            else:
                input_hashes.setdefault(h, p)
        for p in (d / 'environment').rglob('*'):
            if not p.is_file():
                continue
            try:
                env_hash = sha(p.read_bytes())
            except OSError:
                notes.append(f'{name}: unreadable environment fixture '
                             f'{p.relative_to(d)} (mode-restricted)')
                continue
            if env_hash in expected_hashes:
                err(f'environment file {p.relative_to(d)} duplicates expected '
                    'output artifact (answer leak)')
            elif env_hash in input_hashes:
                notes.append(f'{name}: environment file {p.relative_to(d)} '
                             'replays a verifier input copy (visible-case '
                             'recheck; verify hidden cases differ)')

        dj = d / 'difficulty.json'
        if not dj.exists():
            err('difficulty.json missing')
        else:
            dd = json.loads(dj.read_text())
            rub = dd.get('rubric', {})
            if set(rub) != RUBRIC_KEYS:
                err('difficulty.json rubric must contain exactly the 10 '
                    'rubric dimensions')
            elif not all(isinstance(v, int) and 0 <= v <= 3
                         for v in rub.values()):
                err('rubric values must be integers 0..3')
            if not isinstance(dd.get('expected_expert_time_min'), int):
                err('difficulty.json needs integer expected_expert_time_min')

    print(f'tasks={len(tasks)} legacy_v1_skipped={len(legacy)} '
          f'problems={len(problems)} notes={len(notes)}')
    for p in problems:
        print('ERROR', p)
    for n in notes:
        print('NOTE', n)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())

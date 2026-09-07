#!/usr/bin/env python3
"""Collect harbor trials into the published record layout.

Output: OUT/<harness>/<provider>/<model>/<task>/{metadata.json,trajectory.json,
        verifier/reward.txt, verifier/test-stdout.txt}
matching the published format exactly, for use as an --overlay to
tools/assemble_publish.py.

Jobs are named on the command line so any run can be collected, not just the v3.2
drift-canyon restoration this started as:

  --job v33-pi-glm:pi:z-ai/glm-5.3-flash:openrouter/z-ai/glm-5.3-flash

The four fields are job-name:harness:model-in-the-path:model-in-metadata. Harbor
keeps the whole -m string for claude-code, so its metadata model is the bare
OpenRouter slug while pi and terminus-2 carry the openrouter/ prefix.

Every task found in a job is collected unless --task narrows it. It fails closed:
a missing job, a job with no trials, or a trial with no verifier/reward.txt is an
error, not a skip. The original printed SKIP and carried on, and its copy loop
wrote reward.txt only `if src.exists()`, which is how records with no reward
reached the published tree.
"""
import argparse, json, os, re, sys
from pathlib import Path

DEFAULT_JOBS = Path('/home/ee/general-eval-runs/jobs')
DEFAULT_OUT = Path('/tmp/v33-stage')

# The v3.2 drift-canyon jobs, kept as the default so the historical invocation
# still works without arguments.
PAIRS = {
    'pi-glm-v32':     ('pi',         'z-ai/glm-5.3-flash',                'openrouter/z-ai/glm-5.3-flash'),
    'pi-ds-v32':      ('pi',         'deepseek/deepseek-v4-flash-0731',   'openrouter/deepseek/deepseek-v4-flash-0731'),
    'claude-glm-v32': ('claude-code','z-ai/glm-5.3-flash',                'z-ai/glm-5.3-flash'),
    'claude-ds-v32':  ('claude-code','deepseek/deepseek-v4-flash-0731',   'deepseek/deepseek-v4-flash-0731'),
    't2-glm-v32':     ('terminus-2', 'z-ai/glm-5.3-flash',                'openrouter/z-ai/glm-5.3-flash'),
    't2-ds-v32':      ('terminus-2', 'deepseek/deepseek-v4-flash-0731',   'openrouter/deepseek/deepseek-v4-flash-0731'),
}

# v3.1 tool definitions, copied verbatim so records match the published schema.
T2_TOOL = {
    'type': 'function',
    'function': {
        'name': 'bash_command',
        'description': ("Send keystrokes to the task's tmux terminal "
                        "(terminus-2 protocol)."),
        'parameters': {'type': 'object',
                       'properties': {'command': {'type': 'string'}},
                       'required': ['command']},
    },
}
PI_TOOLS = [
    {'type': 'function',
     'function': {'name': 'bash',
                  'description': 'Execute a shell command in the working directory; returns stdout/stderr.',
                  'parameters': {'type': 'object',
                                 'properties': {'command': {'type': 'string'},
                                                'timeout': {'type': 'number'}},
                                 'required': ['command']}}},
    {'type': 'function',
     'function': {'name': 'read',
                  'description': 'Read the contents of a file.',
                  'parameters': {'type': 'object',
                                 'properties': {'path': {'type': 'string'}},
                                 'required': ['path']}}},
    {'type': 'function',
     'function': {'name': 'edit',
                  'description': 'Edit a file with exact text replacement.',
                  'parameters': {'type': 'object',
                                 'properties': {'path': {'type': 'string'},
                                                'edits': {'type': 'array'}},
                                 'required': ['path', 'edits']}}},
    {'type': 'function',
     'function': {'name': 'write',
                  'description': 'Write content to a file (creates or overwrites).',
                  'parameters': {'type': 'object',
                                 'properties': {'path': {'type': 'string'},
                                                'content': {'type': 'string'}},
                                 'required': ['path', 'content']}}},
]


def trial_dirs_by_task(job: Path, only_tasks=None):
    """Map task -> trial dir under a harbor job.

    Harbor writes `<task>__<id>/` trial directories. Several attempts at one task
    can exist, so the last by name wins, matching collect_run.py.

    A trial with exception.txt but no result.json is still included. Harbor can
    record the exception and then hang in artifact collection, which leaves the
    outcome on disk with no result.json; v1-item-043-hard sat that way for over
    half an hour after hitting its 7200 s budget. Discarding the trial would lose
    a result that was actually determined, and silently dropping it is how v3.2
    ended up publishing records with no reward.
    """
    best = {}
    for td in sorted(p for p in job.glob('*__*/') if p.is_dir()):
        task = td.name.split('__')[0]
        if only_tasks and task not in only_tasks:
            continue
        ranked = (td / 'result.json').exists()
        prev = best.get(task)
        # prefer a trial that has result.json; otherwise take the later name
        if prev is None or ranked >= (prev[1] / 'result.json').exists():
            best[task] = (td, ranked)
    return {t: v[0] for t, v in best.items()}


def exception_from_file(trial: Path):
    """Exception type recorded in exception.txt, when result.json is absent."""
    p = trial / 'exception.txt'
    if not p.exists():
        return ''
    text = p.read_text(errors='replace')
    m = re.findall(r'harbor\.trial\.errors\.(\w+)|\b(\w*(?:Timeout|Error|Exception))\b:', text)
    for a, b in reversed(m):
        name = a or b
        if name and name not in ('CancelledError',):
            return name
    return ''


def norm_pi(trial: Path, model: str, task: str):
    sess = sorted((trial / 'agent/pi/sessions').glob('*.jsonl'))[-1]
    messages, tools_used = [], set()
    version = None
    for line in sess.read_text().splitlines():
        e = json.loads(line)
        if e.get('type') == 'session':
            continue
        if e.get('type') != 'message':
            continue
        m = e['message']
        role = m.get('role')
        if role == 'user':
            messages.append({'role': 'user', 'content': m.get('content')})
        elif role == 'assistant':
            reasoning, tool_calls, texts = None, [], []
            for b in m.get('content') or []:
                bt = b.get('type')
                if bt == 'thinking':
                    reasoning = (reasoning or '') + b.get('thinking', '')
                elif bt == 'toolCall':
                    tool_calls.append({
                        'id': b.get('id'), 'type': 'function',
                        'function': {'name': b.get('name'),
                                     'arguments': b.get('arguments')}})
                    tools_used.add(b.get('name'))
                elif bt == 'text':
                    texts.append({'type': 'text', 'text': b.get('text', '')})
            msg = {'role': 'assistant',
                   'content': texts if texts else None,
                   'reasoning_content': reasoning,
                   'reasoning_status': 'present' if reasoning else 'absent'}
            if tool_calls:
                msg['tool_calls'] = tool_calls
            messages.append(msg)
        elif role == 'toolResult':
            text = ''.join(b.get('text', '') for b in m.get('content') or []
                           if isinstance(b, dict))
            messages.append({'role': 'tool', 'content': text,
                             'tool_call_id': m.get('toolCallId')})
    pi_txt = (trial / 'agent/pi.txt').read_text(errors='replace')
    mver = re.search(r'pi\s+([0-9]+\.[0-9]+\.[0-9]+)', pi_txt)
    return {
        'agent': 'pi',
        'agent_profile': 'p (lean: no extensions, no skills)',
        'agent_version': f'pi {mver.group(1)} (patched)' if mver else 'pi (patched)',
        'model': model,
        'task': task,
        'tools': PI_TOOLS,
        'tools_used': sorted(tools_used),
        'messages': messages,
        'usage': {'assistant_turns': sum(1 for m in messages
                                         if m['role'] == 'assistant')},
        'reward': None,
        'exception': False,
    }


def norm_t2(trial: Path, model: str, task: str):
    t = json.loads((trial / 'agent/trajectory.json').read_text())
    messages, tools_used = [], set()
    for s in t.get('steps', []):
        role = 'user' if s.get('source') == 'user' else 'assistant'
        messages.append({'role': role,
                         'content': [{'type': 'text',
                                      'text': s.get('message', '')}]})
        if role == 'assistant':
            tools_used.add('bash_command')
    return {
        'agent': 'terminus-2',
        'agent_version': t.get('agent', {}).get('version', '2.0.0'),
        'model': model,
        'task': task,
        'tools': [T2_TOOL],
        'tools_used': sorted(tools_used),
        'messages': messages,
        'final_metrics': t.get('final_metrics'),
        'reward': None,
        'exception': False,
    }


def norm_claude(trial: Path, model: str, task: str):
    tp = trial / 'agent/trajectory.json'
    t = json.loads(tp.read_text())
    # harbor writes ATIF-style steps; map to the v3.1 published message format
    messages, tools_used = [], set()
    for s in t.get('steps', []):
        obs = s.get('observation') or {}
        for r in obs.get('results') or []:
            messages.append({'role': 'tool', 'content': r.get('content', ''),
                             'tool_call_id': r.get('source_call_id')})
        if s.get('source') == 'user':
            messages.append({'role': 'user', 'content': [
                {'type': 'text', 'text': s.get('message', '')}]})
            continue
        tc_out = []
        for tc in s.get('tool_calls') or []:
            tc_out.append({'id': tc.get('tool_call_id'), 'type': 'function',
                           'function': {'name': tc.get('function_name'),
                                        'arguments': tc.get('arguments') or {}}})
            tools_used.add(tc.get('function_name'))
        msg = {'role': 'assistant',
               'content': ([{'type': 'text', 'text': s['message']}]
                           if s.get('message') else None),
               'reasoning_content': s.get('reasoning_content')}
        if tc_out:
            msg['tool_calls'] = tc_out
        messages.append(msg)
    return {
        'agent': 'claude-code',
        'agent_version': (t.get('agent') or {}).get('version', '2.1.260')
                         if isinstance(t.get('agent'), dict) else '2.1.260',
        'model': model,
        'task': task,
        'tools': [{'type': 'function', 'function': {'name': n}}
                  for n in sorted(tools_used)],
        'tools_used': sorted(tools_used),
        'messages': messages,
        'final_metrics': t.get('final_metrics'),
        'reward': None,
        'exception': False,
    }


def parse_job_spec(spec):
    """`jobname:harness:model-in-path:model-in-metadata` -> tuple.

    The model strings contain slashes but never colons, so split from the left
    into exactly four fields.
    """
    parts = spec.split(':')
    if len(parts) != 4 or not all(parts):
        raise SystemExit(
            f'--job expects jobname:harness:model:model_meta, got {spec!r}')
    return tuple(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--job', action='append', default=[], metavar='SPEC',
                    help='jobname:harness:model:model_meta; repeatable. '
                         'Defaults to the historical v3.2 drift-canyon pairs.')
    ap.add_argument('--task', action='append', default=[],
                    help='collect only these tasks (repeatable); default is all')
    ap.add_argument('--jobs', type=Path, default=DEFAULT_JOBS,
                    help='directory holding the harbor job dirs')
    ap.add_argument('--out', type=Path, default=DEFAULT_OUT)
    ap.add_argument('--allow-missing', action='store_true',
                    help='downgrade a missing job/trial to a warning; the '
                         'assemble step still refuses to publish the gap')
    args = ap.parse_args()
    JOBS, OUT = args.jobs, args.out
    only = set(args.task) or None

    if args.job:
        pairs = {parse_job_spec(s)[0]: parse_job_spec(s)[1:] for s in args.job}
    else:
        pairs = PAIRS

    errors, written = [], 0
    for jobname, (harness, model_plain, model_meta) in pairs.items():
        job = JOBS / jobname
        if not job.exists():
            msg = f'{jobname}: job directory missing ({job})'
            if args.allow_missing:
                print('WARN ' + msg)
            else:
                errors.append(msg)
            continue
        found = trial_dirs_by_task(job, only)
        if not found:
            msg = f'{jobname}: no trials found under {job}' + \
                  (f' matching {sorted(only)}' if only else '')
            if args.allow_missing:
                print('WARN ' + msg)
            else:
                errors.append(msg)
            continue
        for TASK in sorted(found):
            trial = found[TASK]
            rj = trial / 'result.json'
            if rj.exists():
                res = json.loads(rj.read_text())
                exc = (res.get('exception_info') or {}).get('exception_type') or ''
            else:
                # harbor recorded the exception but never finalized the trial
                res = {}
                exc = exception_from_file(trial)
                if not exc:
                    errors.append(f'{jobname}/{TASK}: trial has neither result.json '
                                  f'nor a readable exception.txt, so its outcome is '
                                  f'unknown and it cannot be published ({trial})')
                    continue
                print(f'  NOTE {jobname}/{TASK}: no result.json; harbor did not '
                      f'finalize, using exception.txt ({exc})')
            agent_timeout = 'Timeout' in exc
            if 'Timeout' in exc and 'Verifier' in exc:
                agent_timeout = False
            vr = (res.get('verifier_result') or {})
            reward = ((vr.get('rewards') or {}).get('reward'))
            try:
                if harness == 'pi':
                    traj = norm_pi(trial, model_meta, TASK)
                elif harness == 'terminus-2':
                    traj = norm_t2(trial, model_meta, TASK)
                else:
                    traj = norm_claude(trial, model_plain, TASK)
            except Exception as e:
                errors.append(f'{jobname}/{TASK}: trajectory normalization failed: {e}')
                continue
            traj['reward'] = reward
            traj['exception'] = bool(exc) and not agent_timeout
            dest = OUT / harness / model_plain / TASK
            (dest / 'verifier').mkdir(parents=True, exist_ok=True)
            (dest / 'trajectory.json').write_text(json.dumps(traj, indent=1))
            # Verifier artifacts. A missing reward.txt is not automatically a
            # defect: harbor skips the verifier phase entirely when the agent
            # exhausts its own declared timeout, which leaves result.json with
            # exception_type=AgentTimeoutError, verifier_result=null and an empty
            # test-stdout.txt. That is the mechanism behind every one of the 22
            # v3.2 records that shipped unscoreable.
            #
            # audit_run_rewards.py already classifies this: AgentTimeoutError is
            # TIMEOUT_FAIL and scores 0 under the strict convention, because an
            # agent that cannot finish inside the task's own budget has not
            # solved it. VerifierTimeoutError is the verifier's fault, not the
            # agent's, so scoring it 0 would be wrong and it needs review.
            # Anything else is INFRA and the trial is invalid.
            reward_provenance = 'verifier'
            for f in ('reward.txt', 'test-stdout.txt'):
                src = trial / 'verifier' / f
                if src.exists():
                    (dest / 'verifier' / f).write_bytes(src.read_bytes())
                    continue
                if f != 'reward.txt':
                    # stdout is diagnostics; an agent timeout legitimately leaves
                    # it empty, and harbor usually creates the file anyway
                    (dest / 'verifier' / f).write_text('')
                    continue
                if exc == 'AgentTimeoutError' and not agent_timeout:
                    errors.append(f'{jobname}/{TASK}: AgentTimeoutError but the '
                                  f'timeout was classified as the verifier\'s; '
                                  f'refusing to guess a reward')
                    continue
                if exc == 'AgentTimeoutError':
                    (dest / 'verifier' / 'reward.txt').write_text('0\n')
                    reward = 0
                    basis = ('result.json' if rj.exists()
                             else 'exception.txt, harbor never wrote result.json')
                    reward_provenance = (
                        'agent-timeout: the agent exhausted the task timeout_sec, '
                        'harbor skipped the verifier phase, scored 0 as '
                        'TIMEOUT_FAIL per audit_run_rewards.py. Evidence from '
                        f'{basis}.')
                    print(f'  NOTE {jobname}/{TASK}: agent timeout, verifier '
                          f'never ran -> reward 0 (TIMEOUT_FAIL, from {basis})')
                    continue
                if exc == 'VerifierTimeoutError':
                    errors.append(f'{jobname}/{TASK}: VerifierTimeoutError with no '
                                  f'reward.txt; the verifier exceeded its budget, '
                                  f'which is not the agent\'s failure. Needs '
                                  f'manual review, not a synthesized 0.')
                    continue
                errors.append(f'{jobname}/{TASK}: trial has no verifier/reward.txt '
                              f'and exception {exc or "none"!r} is not an agent '
                              f'timeout, so the trial is INFRA-invalid and must '
                              f'be re-run ({trial})')
            rp = dest / 'verifier/reward.txt'
            if rp.exists():
                raw = rp.read_text().strip()
                try:
                    val = float(raw.splitlines()[-1]) if raw else None
                except ValueError:
                    val = None
                if val not in (0.0, 1.0):
                    errors.append(f'{jobname}/{TASK}: reward {raw!r} is not '
                                  f'binary (0 or 1)')
            # written last so it can record where the reward actually came from.
            # A synthesized TIMEOUT_FAIL 0 must be distinguishable from a 0 the
            # verifier returned, or the published tree cannot be audited.
            traj['reward'] = reward
            (dest / 'trajectory.json').write_text(json.dumps(traj, indent=1))
            (dest / 'metadata.json').write_text(json.dumps({
                'task': TASK, 'agent': harness, 'model': model_meta,
                'reward': reward, 'agent_timeout': agent_timeout,
                'exception': exc or None,
                'reward_provenance': reward_provenance,
                'source_trial': trial.name}, indent=1) + '\n')
            written += 1
            print(f'{jobname:16s} {TASK:22s} reward={reward} '
                  f'timeout={agent_timeout} msgs={len(traj["messages"])}')

    print(f'\nstaged {written} records from {len(pairs)} jobs into {OUT}')
    if errors:
        print(f'ERRORS: {len(errors)}')
        for e in errors:
            print('  ', e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

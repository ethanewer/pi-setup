#!/usr/bin/env python3
"""Collect drift-canyon v3.2 harbor trials into the published record layout.

Output: OUT/<harness>/<provider>/<model>/<task>/{metadata.json,trajectory.json,
        verifier/reward.txt, verifier/test-stdout.txt}
matching the v3.1 format on HF exactly.
"""
import json, os, re, sys
from pathlib import Path

TASK = 'drift-canyon'
JOBS = Path('/mnt/data/v32-jobs')
OUT = Path('/mnt/data/v32-stage')

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


def trial_dir(job: Path) -> Path:
    cands = sorted(job.glob('*/drift-canyon__*/result.json'))
    if not cands:
        raise SystemExit(f'no trial under {job}')
    return cands[-1].parent


def norm_pi(trial: Path, model: str):
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
        'task': TASK,
        'tools': PI_TOOLS,
        'tools_used': sorted(tools_used),
        'messages': messages,
        'usage': {'assistant_turns': sum(1 for m in messages
                                         if m['role'] == 'assistant')},
        'reward': None,
        'exception': False,
    }


def norm_t2(trial: Path, model: str):
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
        'task': TASK,
        'tools': [T2_TOOL],
        'tools_used': sorted(tools_used),
        'messages': messages,
        'final_metrics': t.get('final_metrics'),
        'reward': None,
        'exception': False,
    }


def norm_claude(trial: Path, model: str):
    tp = trial / 'agent/trajectory.json'
    t = json.loads(tp.read_text())
    # harbor claude-code trajectory: adapt to the v3.1 published schema
    msgs = []
    for m in t.get('messages', []):
        msgs.append(m)
    if not msgs:  # steps-style fallback
        for s in t.get('steps', []):
            role = 'user' if s.get('source') == 'user' else 'assistant'
            msgs.append({'role': role, 'content': [
                {'type': 'text', 'text': s.get('message', '')}]})
    tools_used = sorted({b.get('name') for m in msgs if m.get('role') == 'assistant'
                         for b in (m.get('content') or [])
                         if isinstance(b, dict) and b.get('type') == 'tool_use'
                         and b.get('name')})
    return {
        'agent': 'claude-code',
        'agent_version': t.get('agent_version') or '2.1.260',
        'model': model,
        'task': TASK,
        'tools': t.get('tools', []),
        'tools_used': tools_used,
        'messages': msgs,
        'final_metrics': t.get('final_metrics'),
        'reward': None,
        'exception': False,
    }


def main():
    for jobname, (harness, model_plain, model_meta) in PAIRS.items():
        job = JOBS / jobname
        if not job.exists():
            print(f'SKIP {jobname} (missing)')
            continue
        try:
            trial = trial_dir(job)
        except SystemExit as e:
            print('SKIP', e)
            continue
        res = json.loads((trial / 'result.json').read_text())
        exc = (res.get('exception_info') or {}).get('exception_type') or ''
        agent_timeout = 'Timeout' in exc
        if 'Timeout' in exc and 'Verifier' in exc:
            agent_timeout = False
        reward = res.get('verifier_result', {}).get('rewards', {}).get('reward')
        if harness == 'pi':
            traj = norm_pi(trial, model_meta)
        elif harness == 'terminus-2':
            traj = norm_t2(trial, model_meta)
        else:
            traj = norm_claude(trial, model_plain)
        traj['reward'] = reward
        traj['exception'] = bool(exc) and not agent_timeout
        dest = OUT / harness / model_plain / TASK
        (dest / 'verifier').mkdir(parents=True, exist_ok=True)
        (dest / 'metadata.json').write_text(json.dumps({
            'task': TASK, 'agent': harness, 'model': model_meta,
            'reward': reward, 'agent_timeout': agent_timeout,
            'source_trial': trial.name}, indent=1) + '\n')
        (dest / 'trajectory.json').write_text(json.dumps(traj, indent=1))
        for f in ('reward.txt', 'test-stdout.txt'):
            src = trial / 'verifier' / f
            if src.exists():
                (dest / 'verifier' / f).write_bytes(src.read_bytes())
        print(f'{jobname:16s} -> {dest.relative_to(OUT)}  reward={reward} '
              f'timeout={agent_timeout} msgs={len(traj["messages"])}')


if __name__ == '__main__':
    main()

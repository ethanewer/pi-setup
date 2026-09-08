#!/usr/bin/env python3
"""Check that a trial's agent was actually reached by the model.

A run where the provider never answered looks exactly like a run where the model
did badly: both end in a zero, and both leave a trial directory on disk. The only
thing separating them is evidence that the model produced turns. Publishing the
first kind charges an outage to the model; re-running the second kind re-rolls a
genuine result. So this is a publish gate, not a diagnostic.

Two real incidents motivate it.

Nineteen trials from the original v3.2 run window timed out having produced no
assistant turn at all -- eight terminus-2 inside _query_llm, six claude-code hung
mid-stream behind 31,983 lines of thinking_tokens heartbeat, five pi whose log
stopped at message_end for the user prompt. Each burned its full 1200-1800 s
budget and scored 0 under TIMEOUT_FAIL. Re-run, sixteen of them passed.

A later re-run of six claude-code trials omitted ANTHROPIC_BASE_URL and
ANTHROPIC_API_KEY, so claude-code never reached OpenRouter and returned one
synthetic message with input_tokens:0 before exiting 1. Five of six failed
identically. Nothing in the reward files distinguished that from a model that
tried and lost.

The criterion is turns, not token accounting. claude-code reports input_tokens and
total_cost_usd only in its final result event, which never lands when harbor kills
the CLI on an agent timeout -- ashen-vane did 58 real turns and 25 tool calls,
reported zero usage, and passed. An earlier version of this check used the usage
fields and wrongly condemned four valid runs, three of which had passed.

Exit code is 1 if any trial shows no real model turn, so it can gate a publish.

Usage:
  python3 tools/check_agent_actually_ran.py --job DIR [--harness NAME]
  python3 tools/check_agent_actually_ran.py --tree PUBLISHED_ROOT
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _jsonl_events(path: Path):
    try:
        text = path.read_text(errors='replace')
    except Exception:
        return
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith('{'):
            continue
        try:
            yield json.loads(line)
        except Exception:
            continue


def claude_code_evidence(trial: Path):
    """Real assistant turns and tool_use blocks from the CLI's stream log."""
    real = synth = tool_use = tool_result = 0
    log = trial / 'agent/claude-code.txt'
    for e in _jsonl_events(log) if log.is_file() else ():
        et = e.get('type')
        if et == 'assistant':
            m = e.get('message') or {}
            model = m.get('model')
            if model == '<synthetic>':
                synth += 1
            elif model:
                real += 1
            for b in m.get('content') or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    tool_use += 1
        elif et == 'user':
            for b in ((e.get('message') or {}).get('content') or []):
                if isinstance(b, dict) and b.get('type') == 'tool_result':
                    tool_result += 1
    # The session jsonl is a second, independent witness.
    for sj in (trial / 'agent/sessions/projects').rglob('*.jsonl'):
        for e in _jsonl_events(sj):
            m = e.get('message') or {}
            if e.get('type') == 'assistant' and m.get('role') == 'assistant':
                for b in m.get('content') or []:
                    if isinstance(b, dict) and b.get('type') == 'tool_use':
                        tool_use += 1
    return {'real_assistant_turns': real, 'synthetic_turns': synth,
            'tool_use': tool_use, 'tool_result': tool_result,
            'acted': real > 0 or tool_use > 0}


def terminus2_evidence(trial: Path):
    """Steps carrying an observation or a tool call, from harbor's trajectory."""
    tj = trial / 'agent/trajectory.json'
    if not tj.is_file():
        return {'steps': 0, 'observations': 0, 'tool_calls': 0, 'acted': False}
    try:
        steps = json.loads(tj.read_text()).get('steps', [])
    except Exception:
        return {'steps': 0, 'observations': 0, 'tool_calls': 0, 'acted': False}
    obs = sum(1 for s in steps if (s.get('observation') or {}).get('results'))
    tc = sum(1 for s in steps if s.get('tool_calls'))
    # A single step holding only the opening prompt is the stall signature.
    return {'steps': len(steps), 'observations': obs, 'tool_calls': tc,
            'acted': obs > 0 or tc > 0 or len(steps) > 1}


def pi_evidence(trial: Path):
    """Assistant turns from pi's session jsonl, falling back to its stream log."""
    real = tool_use = 0
    sess = sorted((trial / 'agent/pi/sessions').glob('*.jsonl'))
    for sj in sess:
        for e in _jsonl_events(sj):
            if e.get('type') != 'message':
                continue
            m = e.get('message') or {}
            if m.get('role') == 'assistant':
                real += 1
                for b in m.get('content') or []:
                    if isinstance(b, dict) and b.get('type') == 'toolCall':
                        tool_use += 1
    if real == 0:
        # No session file: harbor never got one written. The stream log still shows
        # whether an assistant turn began.
        log = trial / 'agent/pi.txt'
        if log.is_file():
            for e in _jsonl_events(log):
                m = e.get('message') or {}
                if m.get('role') == 'assistant':
                    real += 1
    return {'real_assistant_turns': real, 'tool_use': tool_use,
            'session_files': len(sess), 'acted': real > 0 or tool_use > 0}


EVIDENCE = {'claude-code': claude_code_evidence,
            'terminus-2': terminus2_evidence,
            'pi': pi_evidence}


def detect_harness(trial: Path):
    cfg = trial / 'config.json'
    if cfg.is_file():
        try:
            ag = json.loads(cfg.read_text()).get('agent')
        except Exception:
            ag = None
        if isinstance(ag, dict):
            name = ag.get('name') or ''
            if name == 'p_agent:PAgent':
                return 'pi'
            if name in EVIDENCE:
                return name
    if (trial / 'agent/claude-code.txt').is_file():
        return 'claude-code'
    if (trial / 'agent/pi.txt').is_file() or (trial / 'agent/pi').is_dir():
        return 'pi'
    if (trial / 'agent/terminus_2.pane').is_file():
        return 'terminus-2'
    return None


def check_trial(trial: Path, harness: str | None):
    h = harness or detect_harness(trial)
    fn = EVIDENCE.get(h)
    if fn is None:
        return {'harness': h, 'acted': None, 'note': 'unknown harness'}
    ev = fn(trial)
    ev['harness'] = h
    return ev


def outcome(trial: Path):
    rw = trial / 'verifier/reward.txt'
    reward = rw.read_text().strip() if rw.is_file() else 'ABSENT'
    exc = ''
    rj = trial / 'result.json'
    if rj.is_file():
        try:
            exc = ((json.loads(rj.read_text()).get('exception_info') or {})
                   .get('exception_type') or '')
        except Exception:
            exc = ''
    return reward, exc


# Exceptions that invalidate a trial whatever it managed to do first. Turning
# counts alone are not enough: sable-quill produced one real assistant turn and no
# tool use before the provider dropped the connection, so it looks like a run that
# acted, but it measured nothing. AgentTimeoutError is deliberately absent -- a
# timeout after real work is a legitimate result and must be published.
INFRA_EXCEPTIONS = {
    'AgentSetupTimeoutError': 'the agent never finished starting, so it never ran',
    'ApiConnectionClosedError': 'the provider dropped the connection mid-run',
    'ApiConnectionError': 'the provider connection failed',
    'NonZeroAgentExitCodeError': 'the agent CLI exited non-zero',
}


def infra_fault(trial: Path, exc: str):
    """Return a reason this trial is infrastructure-invalid, or None."""
    if exc in INFRA_EXCEPTIONS:
        return INFRA_EXCEPTIONS[exc]
    if exc == 'RuntimeError':
        et = trial / 'exception.txt'
        text = ''
        if et.is_file():
            try:
                text = et.read_text(errors='replace')
            except Exception:
                text = ''
        if 'failed to send non-blocking keys' in text or 'no server running' in text:
            return 'the tmux server vanished mid-run'
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--job', type=Path, help='a harbor job directory of trial dirs')
    ap.add_argument('--trial', type=Path, action='append', default=[],
                    help='a single trial directory; repeatable')
    ap.add_argument('--harness', choices=sorted(EVIDENCE),
                    help='force the harness instead of detecting it')
    args = ap.parse_args()

    trials = list(args.trial)
    if args.job:
        trials += sorted(p for p in args.job.glob('*__*/') if p.is_dir())
    if not trials:
        print('no trials given; pass --job or --trial', file=sys.stderr)
        return 2

    rows, never = [], []
    for t in trials:
        ev = check_trial(t, args.harness)
        reward, exc = outcome(t)
        fault = infra_fault(t, exc)
        ev['infra_fault'] = fault
        rows.append((t.name, ev.get('harness') or '?', reward, exc or 'none', ev))
        if ev.get('acted') is False:
            never.append((t.name, reward, exc or 'none', 'no real model turn'))
        elif fault:
            never.append((t.name, reward, exc or 'none', fault))

    keys = ['real_assistant_turns', 'synthetic_turns', 'tool_use', 'tool_result',
            'steps', 'observations', 'tool_calls', 'session_files']
    hdr = ('%-34s %-12s %-7s %-24s ' % ('trial', 'harness', 'reward', 'exception')
           + ' '.join('%-7s' % k[:7] for k in keys) + ' measured')
    print(hdr)
    for name, h, reward, exc, ev in rows:
        cells = ' '.join('%-7s' % (ev[k] if k in ev else '-') for k in keys)
        acted = ev.get('acted')
        verdict = {True: 'yes', False: 'NO', None: '?'}[acted]
        if acted and ev.get('infra_fault'):
            verdict = 'NO*'
        print('%-34s %-12s %-7s %-24s %s %s'
              % (name[:34], h[:12], reward[:7], exc[:24], cells, verdict))
    print('  (* produced model turns but was killed by infrastructure)')

    print()
    faults = [(n, r, e, w) for n, r, e, w in never]
    infra = [f for f in faults if f[3] != 'no real model turn']
    if faults:
        print('NEVER MEASURED: %d of %d trials are not results.' % (len(faults), len(trials)))
        for name, reward, exc, why in faults:
            print('   %-34s reward=%-7s %-26s %s' % (name[:34], reward, exc[:26], why))
        if infra:
            print('(%d of those produced model turns but were killed by infrastructure, '
                  'which is not the same as a model that tried and lost)' % len(infra))
        print('Re-run them; do not publish them.')
        return 1
    unknown = [r for r in rows if r[4].get('acted') is None]
    if unknown:
        print('could not determine %d trial(s); harness unknown' % len(unknown))
        return 2
    print('all %d trials produced real model turns and no infrastructure fault' % len(trials))
    return 0


if __name__ == '__main__':
    sys.exit(main())

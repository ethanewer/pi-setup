#!/usr/bin/env python3
"""Verifier body for zephyr-gasket (executes-deliverable).

Runs independently of the candidate oracle: it re-executes /app/solve.py (and
its per-id / per-game subcommands) and re-derives expected results from the raw
fixtures using /tests/engine.py plus the /app maze interface. Any failing check
zeroes the reward. Always leaves a reward file.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, '/app')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import engine
import mazeapi

REWARD = '/logs/verifier/reward.txt'
VISIBLE_MAZES = ['maze-verdigris', 'maze-brass']
VISIBLE_GAMES = ['kinghand-1', 'kinghand-2']


def reward(v):
    os.makedirs(os.path.dirname(REWARD), exist_ok=True)
    with open(REWARD, 'w') as f:
        f.write(str(v))
    return v


def check_one_maze(d, maze_id):
    ok, _reason = engine.check_maze(d, maze_id, mazeapi)
    return ok


def main():
    ok_all = True
    fails = []

    if not os.path.exists('/app/solve.py'):
        fails.append('missing /app/solve.py')
        ok_all = False
    if not os.path.exists('/app/answer.json'):
        fails.append('missing /app/answer.json')
        ok_all = False

    if ok_all:
        try:
            ans = json.load(open('/app/answer.json'))
        except Exception as exc:
            ok_all = False
            fails.append('answer.json unparsable: %s' % exc)
            ans = {}
        mazes = ans.get('mazes', {})
        games = ans.get('games', {})
        for mid in VISIBLE_MAZES:
            if mid not in mazes:
                ok_all = False
                fails.append('answer.json missing maze %s' % mid)
                continue
            if not check_one_maze(mazes[mid], mid):
                ok_all = False
                fails.append('answer.json maze mismatch %s' % mid)
        for gid in VISIBLE_GAMES:
            pos = json.load(open('/app/games/%s.json' % gid))
            if gid not in games:
                ok_all = False
                fails.append('answer.json missing game %s' % gid)
                continue
            if not engine.check_game(games[gid], pos):
                ok_all = False
                fails.append('visible game mismatch %s' % gid)

    # hidden mazes
    hidden_maze = '/tests/hidden/maze_ids.txt'
    if os.path.exists(hidden_maze):
        for line in open(hidden_maze):
            hid = line.strip()
            if not hid:
                continue
            out = '/tmp/verifier_maze.json'
            subprocess.run(['python3', '/app/solve.py', 'maze', hid, out],
                           capture_output=True, text=True)
            try:
                d = json.load(open(out))
            except Exception:
                ok_all = False
                fails.append('hidden maze produced no json: %s' % hid)
                continue
            if not check_one_maze(d, hid):
                ok_all = False
                fails.append('hidden maze mismatch %s' % hid)

    # hidden games
    hidden_games = '/tests/hidden/games'
    if os.path.isdir(hidden_games):
        for fn in sorted(os.listdir(hidden_games)):
            if not fn.endswith('.json'):
                continue
            pos = json.load(open(os.path.join(hidden_games, fn)))
            out = '/tmp/verifier_game.json'
            subprocess.run(['python3', '/app/solve.py', 'game',
                            os.path.join(hidden_games, fn), out],
                           capture_output=True, text=True)
            try:
                reported = json.load(open(out))
            except Exception:
                ok_all = False
                fails.append('hidden game produced no json: %s' % fn)
                continue
            if not engine.check_game(reported, pos):
                ok_all = False
                fails.append('hidden game mismatch %s' % fn)

    # reference selfcheck
    p = subprocess.run(['python3', '/app/solve.py', 'selfcheck'],
                       capture_output=True, text=True)
    if p.returncode != 0 or 'SELFCHECK-OK=1' not in p.stdout:
        ok_all = False
        fails.append('selfcheck did not confirm full reference coverage')

    if fc := fails:
        print('VERIFIER FAILURES:')
        for fx in fc:
            print('  -', fx)
    print('REWARD=' + ('1' if ok_all else '0'))
    reward(1 if ok_all else 0)


if __name__ == '__main__':
    main()
    sys.exit(0)
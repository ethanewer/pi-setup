# harbor-keystone — slippery-warehouse fetch robot

A cold-chain warehouse floor is slippery: the fetch robot sometimes slips and
executes a random move instead of the commanded one. You must write a trainer
that computes a near-optimal movement policy for this stochastic grid world
and saves it as JSON. The grader re-runs your trainer on unseen floor layouts
and independently scores the resulting policies.

## Working directory

Everything runs from `/app`. Python 3.12 is available as `python3`; the only
third-party package installed (or permitted) is `numpy`. Do not modify any
file already shipped in `/app`.

## Deliverables (both required)

1. `/app/train.py` — a runnable program:
   ```
   python3 /app/train.py [--config C] [--out O]
   ```
   - `--config` : path to a floor config JSON (default `/app/rl_config.json`).
   - `--out` : where to write the policy JSON (default `/app/policy.json`).
   - With no arguments it must read `/app/rl_config.json` and write
     `/app/policy.json`.
   It must work on **any** config conforming to the format below — the grader
   runs it on hidden layouts, so hard-coding the shipped floor is not
   acceptable.

2. `/app/policy.json` — the policy produced by running your trainer with no
   arguments on the shipped config.

## Floor config format

```json
{
  "size": 10,                 // grid is size x size cells, x,y in 0..size-1
  "goal": [8, 7],             // the single goal cell (always a free cell)
  "obstacles": [[3,3],[3,4]], // list of blocked cells, may be empty
  "slip": 0.15,               // slip probability p, 0 <= p < 1
  "gamma": 0.95               // discount factor, 0 < gamma < 1
}
```

A **free cell** is any cell that is neither the goal nor an obstacle.

## Environment dynamics (implement them exactly)

The robot is at some free cell `(x, y)` and picks an intended action
`a in {0,1,2,3}` where the deltas are:

- `0` = up    `(x, y-1)`
- `1` = down  `(x, y+1)`
- `2` = left  `(x-1, y)`
- `3` = right `(x+1, y)`

With probability `1 - p` the intended action is executed; with probability
`p` the robot **slips** and a uniformly random action out of the four is
executed instead (the slip draw is independent of `a` and may coincide with
it). The executed action's delta is then applied:

- If the resulting cell would be outside the grid or is an obstacle, the
  robot **stays** where it was.
- If the resulting cell is the goal, the robot receives reward `+100` and
  the episode **terminates**.
- Otherwise (including a blocked "stay") the robot receives reward `-1`.

The return of a start cell is the discounted sum of rewards
(`gamma^0 r_0 + gamma^1 r_1 + ...`) when following the policy forever.

## What the trainer must produce

`/app/train.py` must compute a **near-optimal policy** for the configured
floor — e.g. by value iteration on the dynamics above (a random or
hand-waved policy will not pass). It must write to `--out` a JSON object:

```json
{
  "size": 10,
  "actions": {"0,0": 1, "8,6": 1, "4,4": 3}
}
```

where `actions` maps **every free cell**, as the string `"x,y"`, to its
chosen action `0..3`. Entries for the goal or obstacle cells are ignored if
present, but a missing free cell makes the policy invalid.

## Grading

The grader re-runs `/app/train.py` on the shipped config and on several
hidden configs (different sizes, goal positions, obstacle layouts, slip
probabilities and discount factors, including a fully deterministic
`slip = 0` floor). For each run it independently computes:

- the **optimal** mean discounted return over all free cells (by its own
  value iteration on exactly the dynamics above), and
- the **exact** mean discounted return of your policy (solved linearly, no
  simulation noise).

Your policy passes a config iff its mean discounted return is at least
**95% of the optimal mean** and it covers every free cell with a legal
action. A config that is missing a required key (or has out-of-range values,
e.g. the goal outside the grid) must make the program exit **non-zero** with
a message on stderr.

There is no network access and no simulation involved in grading; the
criterion is deterministic, so an exactly optimal policy always passes.

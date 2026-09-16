#!/bin/bash
# Oracle for wale-haven. Installs the real solver as the deliverable program,
# runs it on the visible dataset to produce /app/result.json, and writes the
# required decisions document.
#
# The solver implements the half-open convention: a period is [from, to), so a
# reading at the exact instant between two consecutive periods is attributed to
# the period that begins at that instant. The other defensible convention
# ((from, to]) is equally acceptable to the verifier; what matters is that the
# choice is applied uniformly and documented. The oracle does the real work and
# never touches /tests.
set -eu

cp /solution/solver.py /app/aggregate.py
chmod +x /app/aggregate.py

python3 /app/aggregate.py /app/periods.json /app/events.csv /app/result.json

cat > /app/decisions.md <<'EOF'
# Attribution decisions

## Ambiguity: readings recorded at the exact instant a period ends and the next begins

The monitoring specification (`/app/spec.md`) defines each period by a `from`
instant, a `to` instant and the rule that a period "covers the readings
recorded from its start time to its end time". It does not say which period
receives a reading whose timestamp falls exactly on the boundary between two
consecutive periods, and the visible dataset contains such readings (for
example at 08:00:00 and at 16:00:00). Because the totals of both adjacent
periods change depending on the assignment, the choice materially affects the
answer, so the rule has to be fixed explicitly.

## Convention chosen: half-open intervals, [from, to)

A reading is attributed to the period that starts at its timestamp. Each period
includes its start instant and excludes its end instant: `from <= t < to`. A
boundary reading therefore belongs to the next period, never to the period that
just ended.

## Reasoning

Both half-open `[from, to)` and the end-inclusive `(from, to]` reading are
defensible, as long as exactly one is used everywhere: the specification's
"from its start time to its end time" does not resolve which side owns the
shared instant. I chose the half-open convention because it treats each period
as "the readings recorded once that period starts and until the next one
starts", which is the natural reading for a continuous monitoring fleet: a
reading timed at a period boundary is a reading of the new period's conditions,
and the old period's total stays closed at the moment before the boundary. The
decisive property, though, is consistency: the same comparison must be applied
to every period of every dataset, so that no boundary reading is counted twice
and none is dropped. That is what the verifier checks on the hidden datasets.
EOF

echo "oracle produced /app/aggregate.py, /app/result.json and /app/decisions.md"
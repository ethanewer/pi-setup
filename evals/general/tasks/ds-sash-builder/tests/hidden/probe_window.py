#!/usr/bin/env python3
"""ds-sash-builder hidden probe.

Independent SQL-generation reference: renders expected canonical SQL from
raw spec dicts (see the demo spec shape) WITHOUT using the agent's code.
Checks, in order:

  A. visible demo recheck — re-render `demo.DEMO_SPECS` with the reference;
     require `python3 /app/demo.py` stdout AND /app/demo_out.sql to match
     byte-for-byte;
  B. hidden usage matrix — ~20 queries with tables/columns/aliases/functions/
     frames absent from the visible demo, driven through the REAL builder
     API (Qb + qb.window.OverSpec) and compared byte-for-byte;
  C. API surface — qb.window has OverSpec/window_item; window_item output
     spot checks; invalid OverSpec constructions raise ValueError.

Exit 0 on success, 1 on any failure (details on stderr).
"""
import subprocess
import sys

sys.path.insert(0, "/app")

# ---------------------------------------------------------------------------
# Independent reference implementation (canonical rules from the task brief).
# ---------------------------------------------------------------------------

def quote(ident):
    return '"' + str(ident).replace('"', '""') + '"'


def render_order(entry):
    parts = str(entry).split(None, 1)
    if len(parts) == 2 and parts[1].lower() in ('asc', 'desc'):
        return quote(parts[0]) + ' ' + parts[1].upper()
    return quote(parts[0])


def render_bound(bound):
    b = str(bound).strip().lower()
    if b == 'current row':
        return 'CURRENT ROW'
    if b == 'unbounded preceding':
        return 'UNBOUNDED PRECEDING'
    if b == 'unbounded following':
        return 'UNBOUNDED FOLLOWING'
    parts = b.split()
    if len(parts) == 2 and parts[0].isdigit() and parts[1] in (
            'preceding', 'following'):
        return parts[0] + ' ' + parts[1].upper()
    raise ValueError('invalid frame bound: %r' % (bound,))


def render_window_item(alias, ov):
    """Reference render of one window select item from OverSpec kwargs."""
    fn = ov['function'].upper()
    args = tuple(ov.get('args', ()))
    if args:
        call = '%s(%s)' % (fn, quote(args[0]))
    else:
        call = '%s()' % fn
    inner = []
    if ov.get('partition_by'):
        inner.append('PARTITION BY ' + ', '.join(
            quote(c) for c in ov['partition_by']))
    if ov.get('order_by'):
        inner.append('ORDER BY ' + ', '.join(
            render_order(e) for e in ov['order_by']))
    if ov.get('frame') is not None:
        inner.append('ROWS BETWEEN %s AND %s' % (
            render_bound(ov['frame'][0]), render_bound(ov['frame'][1])))
    over_txt = 'OVER (' + (' '.join(inner) if inner else '') + ')'
    return '%s %s AS %s' % (call, over_txt, quote(alias))


def render_query(spec):
    """Reference render of a full query from a spec dict."""
    items = [quote(c) for c in spec.get('select', ())]
    items += [render_window_item(a, ov) for a, ov in spec.get('windows', ())]
    parts = ['SELECT', ', '.join(items), 'FROM', quote(spec['from_'])]
    if spec.get('where'):
        parts.append('WHERE')
        parts.append(' AND '.join(spec['where']))
    if spec.get('order_by'):
        parts.append('ORDER BY')
        parts.append(', '.join(render_order(e) for e in spec['order_by']))
    return ' '.join(parts)


failures = []


def check(label, ok, detail=''):
    if not ok:
        failures.append('%s%s' % (label, (': ' + detail) if detail else ''))


# ---------------------------------------------------------------------------
# A. Visible demo recheck (independent re-render + demo runs + deliverable).
# ---------------------------------------------------------------------------
try:
    import demo
    demo_specs = demo.DEMO_SPECS
except Exception as exc:  # agent library broken -> fail cleanly
    print('probe: cannot import demo specs (agent library broken?): %s'
          % exc, file=sys.stderr)
    sys.exit(1)

try:
    expected_demo = "\n".join(render_query(s) for s in demo_specs) + "\n"
except Exception as exc:
    print('probe: reference render of demo specs failed: %s' % exc,
          file=sys.stderr)
    sys.exit(1)

# A1. The shipped /app/demo_out.sql deliverable must ALREADY contain the
# reference text (checked BEFORE any regeneration so a corrupted or empty
# deliverable fails).
try:
    with open('/app/demo_out.sql', encoding='utf-8') as fh:
        demo_file = fh.read()
    check('/app/demo_out.sql == reference', demo_file == expected_demo,
          'got=%r want=%r' % (demo_file[:160], expected_demo[:160]))
except OSError as exc:
    check('/app/demo_out.sql readable', False, str(exc))

# A2. The demo must still run through the agent library and reproduce the
# reference text (catches a hardcoded demo_out.sql with a broken library).
try:
    r = subprocess.run(['python3', '/app/demo.py'], capture_output=True,
                       text=True, timeout=90)
except Exception as exc:
    r = None
    check('demo run raised', False, repr(exc))

if r is not None:
    check('demo exit code', r.returncode == 0,
          'rc=%s stderr=%s' % (r.returncode, (r.stderr or '')[-300:]))
    if r.returncode == 0:
        check('demo stdout == reference', r.stdout == expected_demo,
              'stdout=%r want=%r' % (r.stdout[:160], expected_demo[:160]))
        try:
            with open('/app/demo_out.sql', encoding='utf-8') as fh:
                regen = fh.read()
            check('demo regenerates /app/demo_out.sql == reference',
                  regen == expected_demo,
                  'got=%r want=%r' % (regen[:160], expected_demo[:160]))
        except OSError as exc:
            check('demo regenerates /app/demo_out.sql', False, str(exc))

# ---------------------------------------------------------------------------
# B. Hidden usage matrix (distinct domain: warehouse/sensor/message data).
# ---------------------------------------------------------------------------
HIDDEN = [
    # (spec dict, interleave_select_window_first)
    (dict(select=("sku", "zone", "qty"), from_="stock", where=(),
          order_by=(), windows=[
              ("zr", {"function": "row_number", "partition_by": ("zone",),
                      "order_by": ("qty desc",)})]), False),
    (dict(select=("sku",), from_="stock", where=("qty > 0",),
          order_by=("zone", "sku"),
          windows=[
              ("zone_total", {"function": "sum", "args": ("qty",),
                              "partition_by": ("zone",),
                              "order_by": ("sku asc",),
                              "frame": ("2 preceding", "current row")})]),
     False),
    (dict(select=("sensor_id", "ts", "value"), from_="reads", where=(),
          order_by=("sensor_id", "ts"),
          windows=[
              ("r", {"function": "rank", "partition_by": ("sensor_id",),
                     "order_by": ("value desc",)}),
              ("d", {"function": "dense_rank",
                     "order_by": ("value desc",)}),
              ("cum", {"function": "sum", "args": ("value",),
                       "partition_by": ("sensor_id",),
                       "order_by": ("ts",),
                       "frame": ("unbounded preceding", "current row")}),
          ]), False),
    (dict(select=("msg_id", "topic", "size"), from_="messages",
          where=("size >= 0",), order_by=("topic", "size desc"),
          windows=[
              ("avg_size", {"function": "avg", "args": ("size",),
                            "partition_by": ("topic",),
                            "frame": ("1 preceding", "1 following")}),
          ]), False),
    (dict(select=("pallet", "count"), from_="warehouse", where=(),
          order_by=(),
          windows=[
              ("grand", {"function": "count", "args": ("pallet",),
                         "frame": ("unbounded preceding",
                                   "unbounded following")}),
          ]), False),
    # empty partition_by + empty window order_by -> OVER ()
    (dict(select=("e",), from_="empty_t", where=(),
          order_by=(),
          windows=[
              ("cnt", {"function": "count", "args": ("e",)}),
          ]), False),
    # partition only, no window order, no frame
    (dict(select=("region", "v"), from_="agg", where=("v is not null",),
          order_by=(),
          windows=[
              ("tot", {"function": "sum", "args": ("v",),
                       "partition_by": ("region",)}),
          ]), False),
    # empty partition, window ORDER BY only
    (dict(select=("t", "v"), from_="seq", where=(),
          order_by=("t",),
          windows=[
              ("run", {"function": "sum", "args": ("v",),
                       "order_by": ("t",),
                       "frame": ("unbounded preceding", "current row")}),
          ]), False),
    # current-row-start edge frame
    (dict(select=("id", "v"), from_="series", where=("v <> 0",),
          order_by=("id desc",),
          windows=[
              ("fwd", {"function": "avg", "args": ("v",),
                       "frame": ("current row", "2 following")}),
          ]), False),
    # symmetric edge frame, no other clauses
    (dict(select=("id", "v"), from_="series", where=(),
          order_by=(),
          windows=[
              ("w", {"function": "avg", "args": ("v",),
                     "frame": ("5 preceding", "5 following")}),
          ]), False),
    # asymmetric frame with unbounded start
    (dict(select=("id", "v"), from_="series", where=(),
          order_by=(),
          windows=[
              ("w", {"function": "sum", "args": ("v",),
                     "frame": ("unbounded preceding", "5 following")}),
          ]), False),
    # frame with only following bounds
    (dict(select=("id", "v"), from_="series", where=(),
          order_by=(),
          windows=[
              ("w", {"function": "count", "args": ("v",),
                     "frame": ("2 following", "5 following")}),
          ]), False),
    # rank over partition without window order
    (dict(select=("k", "g"), from_="groups", where=(),
          order_by=(),
          windows=[
              ("rk", {"function": "rank", "partition_by": ("g",)}),
          ]), False),
    # identifier with an embedded double quote (doubling rule)
    (dict(select=("id",), from_="q\"2024", where=(),
          order_by=(),
          windows=[
              ("n", {"function": "row_number",
                     "partition_by": ("a\"b",)}),
          ]), False),
    # lowercase asc direction renders UPPER CASE
    (dict(select=("x", "y"), from_="t2", where=(),
          order_by=("x asc",),
          windows=[
              ("s", {"function": "sum", "args": ("y",),
                     "partition_by": ("x",),
                     "order_by": ("x asc",),
                     "frame": ("1 preceding", "current row")}),
          ]), False),
    # three windows, no frame, plus where and outer order
    (dict(select=("runner", "race", "time"), from_="results",
          where=("finished = 1",), order_by=("race",), windows=[
              ("by_race", {"function": "rank",
                           "partition_by": ("race",),
                           "order_by": ("time asc",)}),
              ("by_time", {"function": "row_number",
                           "order_by": ("time asc",)}),
              ("cnt", {"function": "count", "args": ("runner",),
                       "partition_by": ("race",)}),
          ]), False),
    # call interleaving: select_window precedes select and from_/where after
    (dict(select=("c",), from_="inter", where=("c >= 1",),
          order_by=("c desc",),
          windows=[
              ("w1", {"function": "dense_rank",
                      "partition_by": ("c",)}),
              ("w2", {"function": "sum", "args": ("c",),
                      "frame": ("unbounded preceding",
                                "unbounded following")}),
          ]), True),
    # avg no frame, partition two columns
    (dict(select=("a", "b", "m"), from_="pairs",
          where=("m is not null",), order_by=(),
          windows=[
              ("m_avg", {"function": "avg", "args": ("m",),
                         "partition_by": ("a", "b"),
                         "frame": ("unbounded preceding",
                                   "current row")}),
          ]), False),
    # count with embedded-quote alias
    (dict(select=("k",), from_="t3", where=(), order_by=(),
          windows=[
              ("odd\"alias", {"function": "count", "args": ("k",)}),
          ]), False),
]

try:
    from qb import Qb
    from qb.window import OverSpec
except Exception as exc:
    print('probe: cannot import agent library: %s' % exc, file=sys.stderr)
    sys.exit(1)

for idx, (spec, interleave) in enumerate(HIDDEN):
    try:
        want = render_query(spec)
    except Exception as exc:
        check('hidden[%d] reference render' % idx, False, repr(exc))
        continue
    try:
        qb = Qb()
        if interleave:
            for alias, ov in spec.get('windows', ()):
                qb.select_window(alias, OverSpec(**ov))
            qb.select(*spec.get('select', ()))
        else:
            qb.select(*spec.get('select', ()))
            for alias, ov in spec.get('windows', ()):
                qb.select_window(alias, OverSpec(**ov))
        qb.from_(spec['from_'])
        if spec.get('where'):
            qb.where(*spec['where'])
        if spec.get('order_by'):
            qb.order_by(*spec['order_by'])
        got = qb.sql()
    except Exception as exc:
        check('hidden[%d] agent run' % idx, False,
              'raised %r (want %r)' % (exc, want))
        continue
    check('hidden[%d] sql' % idx, got == want,
          'got=%r want=%r' % (got[:200], want[:200]))

# ---------------------------------------------------------------------------
# C. API surface spot checks + validation.
# ---------------------------------------------------------------------------
try:
    import qb.window as wmod
    check('window module has OverSpec', hasattr(wmod, 'OverSpec'))
    check('window module has window_item', hasattr(wmod, 'window_item'))
except Exception as exc:
    print('probe: cannot import qb.window: %s' % exc, file=sys.stderr)
    sys.exit(1)

try:
    spot = wmod.window_item(
        'rn', OverSpec(function='row_number', partition_by=('dept',),
                       order_by=('salary desc',)))
    check('window_item spot check',
          spot == 'ROW_NUMBER() OVER (PARTITION BY "dept" '
                  'ORDER BY "salary" DESC) AS "rn"', spot)
except Exception as exc:
    check('window_item spot check', False, repr(exc))

try:
    spot = wmod.window_item(
        'run_total', OverSpec(function='sum', args=('sales',),
                              partition_by=('region',),
                              order_by=('month',),
                              frame=('unbounded preceding', 'current row')))
    check('window_item frame spot check',
          spot == 'SUM("sales") OVER (PARTITION BY "region" ORDER BY "month" '
                  'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) '
                  'AS "run_total"', spot)
except Exception as exc:
    check('window_item frame spot check', False, repr(exc))


def raises_value_error(make):
    try:
        make()
        return False
    except ValueError:
        return True
    except Exception:
        return False


check('unknown function -> ValueError',
      raises_value_error(lambda: OverSpec(function='lag')))
check('aggregate missing arg -> ValueError',
      raises_value_error(lambda: OverSpec(function='sum', args=())))
check('aggregate extra arg -> ValueError',
      raises_value_error(lambda: OverSpec(function='sum', args=('a', 'b'))))
check('ranking with args -> ValueError',
      raises_value_error(lambda: OverSpec(function='rank', args=('x',))))
check('malformed bound -> ValueError',
      raises_value_error(lambda: OverSpec(
          function='avg', args=('x',), frame=('5 sideways', 'current row'))))
check('non-pair frame -> ValueError',
      raises_value_error(lambda: OverSpec(
          function='avg', args=('x',), frame=('a',))))
check('count with one arg is valid',
      not raises_value_error(lambda: OverSpec(function='count', args=('k',))))

# ---------------------------------------------------------------------------
if failures:
    print('probe FAILURES (%d):' % len(failures), file=sys.stderr)
    for f in failures:
        print('  - ' + f, file=sys.stderr)
    sys.exit(1)
print('probe: all checks passed (%d hidden queries, demo recheck, API surface)'
      % len(HIDDEN))
sys.exit(0)
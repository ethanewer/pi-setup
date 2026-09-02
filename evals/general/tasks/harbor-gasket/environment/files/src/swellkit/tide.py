"""Harmonic tide prediction for swellkit.

A forecast is the sum of harmonic constituents evaluated at a given hour:

    h(t) = sum over constituents k of  A_k * cos(2*pi*t / T_k + P_k * pi / 180)

where A_k is the constituent amplitude (metres), T_k its period (hours) and
P_k its epoch phase (degrees).
"""

import math


def parse_constituents(text):
    """Parse a constituent table from text.

    One constituent per line, four comma-separated fields:
    ``name,amplitude,period_hours,phase_degrees``.

    Rules (edge behaviour, contractual):

    * blank lines and lines whose first non-space character is ``#`` are skipped;
    * a row that is not exactly four comma-separated fields, whose numeric
      fields do not parse as floats, or whose period is not strictly greater
      than zero raises ``ValueError`` (the table is malformed);
    * names are not validated (any non-empty token is accepted).
    """
    rows = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) != 4:
            raise ValueError("constituent row must have 4 comma-separated fields: %r" % line)
        try:
            name = parts[0]
            amp = float(parts[1])
            period = float(parts[2])
            phase = float(parts[3])
        except ValueError:
            raise ValueError("malformed constituent row: %r" % line)
        if not (period > 0.0):
            raise ValueError("constituent period must be > 0: %r" % line)
        rows.append((name, amp, period, phase))
    return rows


def height_hours(t_hours, text):
    """Predicted water height (metres) at ``t_hours`` for the constituent table ``text``.

    An empty table (only comments/blank lines) forecasts exactly ``0.0``.
    ``t_hours`` may be negative or fractional.
    """
    rows = parse_constituents(text)
    rad = math.pi / 180.0
    return sum(
        amp * math.cos(2.0 * math.pi * t_hours / period + phase * rad)
        for _name, amp, period, phase in rows
    )


def forecast_file(path, t_hours=0.0):
    """Forecast ``t_hours`` from the constituent table stored in ``path``."""
    with open(path, "r") as fh:
        return height_hours(t_hours, fh.read())


if __name__ == "__main__":
    import sys

    path = sys.argv[1]
    hour = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    print("%.10f" % forecast_file(path, hour))

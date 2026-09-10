#!/usr/bin/env python3
"""Deterministic builder for the conduit-tarn task repository.

Builds /app/conduit, a self-authored Python git repository with a 40-commit
history, a green pytest suite, release tags, and one disguised regression
(introduced at a fixed commit). Everything the agent sees is generated here so
the fixture is reproducible and nothing is hand-typed twice.

Run as root at image build time:  python3 /app/gen_repo.py
"""
import os
import subprocess
import sys
from datetime import datetime, timezone

REPO = os.environ.get("CONDUIT_REPO", "/app/conduit")
MANIFEST = os.environ.get("CONDUIT_MANIFEST", "/etc/conduit-initial.env")

AUTHORS = [
    ("l.okafor", "l.okafor@tarn.local"),
    ("m.reyes", "m.reyes@tarn.local"),
    ("p.vandermeer", "p.vandermeer@tarn.local"),
    ("a.kahn", "a.kahn@tarn.local"),
    ("t.sawyer", "t.sawyer@tarn.local"),
]

BASE_EPOCH = int(datetime(2024, 11, 4, tzinfo=timezone.utc).timestamp())
DAY = 86400


def git(args, **kw):
    subprocess.run(["git", "-C", REPO] + args, check=True, **kw)


def commit(msg, index):
    author = AUTHORS[index % len(AUTHORS)]
    when = "@%d" % (BASE_EPOCH + index * 3 * DAY)
    env = dict(os.environ)
    env["GIT_AUTHOR_NAME"] = author[0]
    env["GIT_AUTHOR_EMAIL"] = author[1]
    env["GIT_COMMITTER_NAME"] = author[0]
    env["GIT_COMMITTER_EMAIL"] = author[1]
    env["GIT_AUTHOR_DATE"] = when
    env["GIT_COMMITTER_DATE"] = when
    git(["add", "-A"])
    git(["commit", "-q", "-m", msg], env=env)


# ---------------------------------------------------------------------------
# File content versions. path -> list of version texts; version i ships at the
# commit(s) that reference it. The LAST version of each file is the state the
# agent sees.
# ---------------------------------------------------------------------------

CONTENT = {}

CONTENT["README.md"] = [
    # v1 (commit 1)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Status

Early skeleton. Parsing and the canonical document are being built out.
""",
    # v2 (commit 12)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Usage

    python3 -m conduit feed.csv out.json

The vendor feed is a CSV (see `docs/format.md` for the exact schema). The
canonical document is written to `out.json`.

## Development

Run the test suite from the repository root:

    python3 -m pytest -q tests/
""",
    # v3 (commit 22)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Usage

    python3 -m conduit feed.csv out.json

The vendor feed is a CSV (see `docs/format.md` for the exact schema). The
canonical document is written to `out.json`.

## Samples

- `samples/feed_single.csv` - single-fill orders
- `samples/feed_mixed.csv` - mixed instruments and sides
- `samples/feed_multi_line.csv` - multi-leg basket orders (several rows share
  one order id)

## Development

Run the test suite from the repository root:

    python3 -m pytest -q tests/
""",
    # v4 (commit 29)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Usage

    python3 -m conduit feed.csv out.json

Pass `-` as the feed path to read the feed from stdin. The vendor feed is a
CSV (see `docs/format.md` for the exact schema). The canonical document is
written to `out.json`.

## Samples

- `samples/feed_single.csv` - single-fill orders
- `samples/feed_mixed.csv` - mixed instruments and sides
- `samples/feed_multi_line.csv` - multi-leg basket orders (several rows share
  one order id)

## Development

Run the test suite from the repository root:

    python3 -m pytest -q tests/

## Troubleshooting

- `conduit: unexpected header`: the feed is not a recognised vendor dialect;
  make sure the header row names the six columns in order.
- `conduit: feed contains no rows`: every row failed validation; inspect the
  warnings in the output document after fixing the rows.
""",
    # v5 (commit 39)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Usage

    python3 -m conduit feed.csv out.json

Pass `-` as the feed path to read the feed from stdin. The vendor feed is a
CSV (see `docs/format.md` for the exact schema). The canonical document is
written to `out.json`.

## Samples

- `samples/feed_single.csv` - single-fill orders
- `samples/feed_mixed.csv` - mixed instruments and sides
- `samples/feed_multi_line.csv` - multi-leg basket orders (several rows share
  one order id)

## Volume

The daily vendor dump is ~2.4M rows peak. The pipeline is single-pass and
streams through the CSV reader; keep the caching parser in `conduit/orders.py`
intact, it is the hot path.

## Development

Run the test suite from the repository root:

    python3 -m pytest -q tests/

## Troubleshooting

- `conduit: unexpected header`: the feed is not a recognised vendor dialect;
  make sure the header row names the six columns in order.
- `conduit: feed contains no rows`: every row failed validation; inspect the
  warnings in the output document after fixing the rows.
""",
    # v6 (commit 40)
    """# conduit

Internal tool for the Tarn trading desk: normalises vendor order feeds into a
canonical order document.

## Usage

    python3 -m conduit feed.csv out.json

Pass `-` as the feed path to read the feed from stdin. The vendor feed is a
CSV (see `docs/format.md` for the exact schema). The canonical document is
written to `out.json`.

## Samples

- `samples/feed_single.csv` - single-fill orders
- `samples/feed_mixed.csv` - mixed instruments and sides
- `samples/feed_multi_line.csv` - multi-leg basket orders (several rows share
  one order id)

## Volume

The daily vendor dump is ~2.4M rows peak. The pipeline is single-pass and
streams through the CSV reader; keep the caching parser in `conduit/orders.py`
intact, it is the hot path.

## Development

Run the test suite from the repository root:

    python3 -m pytest -q tests/

## Known limits

- Feeds must carry a header row naming the six columns in order.
- The canonical document keeps warnings for skipped rows; rows that fail
  structure checks do not abort the run.
- Summary fields are rounded to two decimals with Python's built-in `round`.

## Troubleshooting

- `conduit: unexpected header`: the feed is not a recognised vendor dialect;
  make sure the header row names the six columns in order.
- `conduit: feed contains no rows`: every row failed validation; inspect the
  warnings in the output document after fixing the rows.
""",
]

CONTENT["CHANGELOG.md"] = [
    # v1 (commit 30)
    """# Changelog

## [0.9.0] - 2025-01-17

### Added

- Bundle of feed-dialect and validation hardening (see git history).
""",
    # v2 (commit 35)
    """# Changelog

## [1.0.0] - 2025-02-02

### Added

- First stable release of the canonical order document.
- Fee, net and per-order side lists in the canonical document.
- Semantic validation wired into feed parsing.

### Changed

- Fill ordering is canonical across feeds (timestamp, then feed position).

## [0.9.0] - 2025-01-17

### Added

- Bundle of feed-dialect and validation hardening (see git history).
""",
    # v3 (commit 37)
    """# Changelog

## [1.0.1] - 2025-02-10

### Fixed

- Development-notes typos; no behavioural change.

## [1.0.0] - 2025-02-02

### Added

- First stable release of the canonical order document.
- Fee, net and per-order side lists in the canonical document.
- Semantic validation wired into feed parsing.

### Changed

- Fill ordering is canonical across feeds (timestamp, then feed position).

## [0.9.0] - 2025-01-17

### Added

- Bundle of feed-dialect and validation hardening (see git history).
""",
]

CONTENT["docs/format.md"] = [
    # v1 (commit 12)
    """# Feed and canonical document format

## Vendor feed

CSV with a header row and one fill per line:

    order_id,side,instrument,quantity,price,timestamp

- `order_id` - non-empty string. Basket orders span **several rows** that
  share one order id; every fill must survive into the canonical document.
- `side` - `BUY` or `SELL`.
- `instrument` - non-empty string.
- `quantity` - positive integer.
- `price` - positive number.
- `timestamp` - ISO-8601, `YYYY-MM-DDTHH:MM:SS`.

Rows that fail parsing are skipped and reported in the `warnings` list (with
the physical line number) instead of aborting the run.

## Canonical document

    {"orders": [ ... ], "warnings": [ ... ]}

One entry per distinct order id, in the order the order id first appears in
the feed:

    {"order_id": "...", "fills": [...], "fill_count": N, "gross": G}

- `fills` - one object per fill row, fields `seq`, `side`, `instrument`,
  `quantity`, `price`, `timestamp`. `seq` is the 1-based position of the fill
  among the accepted rows.
- `fill_count` - the number of fills.
- `gross` - sum of `quantity * price` per fill, rounded to two decimals.
""",
    # v2 (commit 19)
    """# Feed and canonical document format

## Vendor feed

CSV with a header row and one fill per line:

    order_id,side,instrument,quantity,price,timestamp

- `order_id` - non-empty string. Basket orders span **several rows** that
  share one order id; every fill must survive into the canonical document.
- `side` - `BUY` or `SELL`.
- `instrument` - non-empty string.
- `quantity` - positive integer.
- `price` - positive number.
- `timestamp` - ISO-8601, `YYYY-MM-DDTHH:MM:SS` (fractional seconds allowed).

Rows that fail parsing or validation are skipped and reported in the
`warnings` list (with the physical line number) instead of aborting the run.

## Canonical document

    {"orders": [ ... ], "warnings": [ ... ]}

One entry per distinct order id, in the order the order id first appears in
the feed:

    {"order_id": "...", "fills": [...], "fill_count": N,
     "gross": G, "fee": F, "net": N, "sides": [...]}

- `fills` - one object per fill row, fields `seq`, `side`, `instrument`,
  `quantity`, `price`, `timestamp`. `seq` is the 1-based position of the fill
  among the accepted rows.
- `fill_count` - the number of fills.
- `gross` - sum of `quantity * price` per fill, rounded to two decimals.
- `fee` - `round(gross * 0.0015, 2)`.
- `net` - `round(gross - fee, 2)`.
- `sides` - the distinct sides in the order, in order of first appearance.

All `round(x, 2)` calls use Python's built-in rounding.
""",
    # v3 (commit 20)
    """# Feed and canonical document format

## Vendor feed

CSV with a header row and one fill per line:

    order_id,side,instrument,quantity,price,timestamp

- `order_id` - non-empty string. Basket orders span **several rows** that
  share one order id; every fill must survive into the canonical document.
- `side` - `BUY` or `SELL`.
- `instrument` - non-empty string.
- `quantity` - positive integer.
- `price` - positive number.
- `timestamp` - ISO-8601, `YYYY-MM-DDTHH:MM:SS` (fractional seconds allowed).

Rows that fail parsing or validation are skipped and reported in the
`warnings` list (with the physical line number) instead of aborting the run.

## Canonical document

    {"orders": [ ... ], "warnings": [ ... ]}

One entry per distinct order id, in the order the order id first appears in
the feed:

    {"order_id": "...", "fills": [...], "fill_count": N,
     "gross": G, "fee": F, "net": N, "sides": [...]}

- `fills` - one object per fill row, fields `seq`, `side`, `instrument`,
  `quantity`, `price`, `timestamp`. `seq` is the 1-based position of the fill
  among the accepted rows. Within an order the fills are ordered by
  `timestamp`, breaking ties by `seq`.
- `fill_count` - the number of fills. Every fill row of a basket order must
  appear here.
- `gross` - sum of `quantity * price` per fill, rounded to two decimals.
- `fee` - `round(gross * 0.0015, 2)`.
- `net` - `round(gross - fee, 2)`.
- `sides` - the distinct sides in the order, in order of first appearance.

All `round(x, 2)` calls use Python's built-in rounding.
""",
]

CONTENT["docs/contributing.md"] = [
    """# Development notes

- Keep the canonical document schema stable; downstream consumers parse it.
- New behaviour ships with tests under `tests/`.
- Commits follow the conventional-commit style used throughout this repo.
- Field ordering in `conduit/format.py` is load-bearing: JSON key order is
  part of the contract.
""",
]

CONTENT[".gitignore"] = [
    """__pycache__/
*.py[cod]
.pytest_cache/
""",
    """__pycache__/
*.py[cod]
.pytest_cache/
*.swp
*.swo
.DS_Store
.idea/
""",
]

CONTENT["conduit/__init__.py"] = [
    '"""conduit: deterministic order-feed normaliser for the Tarn trading desk."""\n'
    '\n'
    '__version__ = "0.1.0"\n',
    '"""conduit: deterministic order-feed normaliser for the Tarn trading desk."""\n'
    '\n'
    '__version__ = "0.9.0"\n',
    '"""conduit: deterministic order-feed normaliser for the Tarn trading desk."""\n'
    '\n'
    '__version__ = "1.0.0"\n',
    '"""conduit: deterministic order-feed normaliser for the Tarn trading desk."""\n'
    '\n'
    '__version__ = "1.0.1"\n',
]

CONTENT["conduit/errors.py"] = [
    '"""Exceptions raised by the conduit pipeline."""\n'
    '\n'
    '\n'
    'class ConduitError(Exception):\n'
    '    """Base class for all conduit errors."""\n'
    '\n'
    '\n'
    'class FeedFormatError(ConduitError):\n'
    '    """Raised when a feed cannot be parsed as a known vendor dialect."""\n'
    '\n'
    '\n'
    'class FieldValidationError(ConduitError):\n'
    '    """Raised when a row fails field-level validation."""\n',
]

CONTENT["conduit/orders.py"] = [
    # v1 (commit 2)
    '"""Row-level model for a single fill record in an order feed."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'from .errors import FeedFormatError\n'
    '\n'
    'FIELDS = ("order_id", "side", "instrument", "quantity", "price", '
    '"timestamp")\n'
    '\n'
    '\n'
    'class OrderRow:\n'
    '    """One fill row."""\n'
    '\n'
    '    __slots__ = ("order_id", "side", "instrument", "quantity", "price",\n'
    '                 "timestamp", "seq")\n'
    '\n'
    '    def __init__(self, order_id, side, instrument, quantity, price,\n'
    '                 timestamp, seq):\n'
    '        self.order_id = order_id\n'
    '        self.side = side\n'
    '        self.instrument = instrument\n'
    '        self.quantity = quantity\n'
    '        self.price = price\n'
    '        self.timestamp = timestamp\n'
    '        self.seq = seq\n'
    '\n'
    '    @classmethod\n'
    '    def from_fields(cls, values, seq):\n'
    '        """Build a row from raw CSV fields; bad rows raise '
    'FeedFormatError."""\n'
    '        if len(values) != len(FIELDS):\n'
    '            raise FeedFormatError("row %d: expected %d fields, got %d"\n'
    '                                   % (seq, len(FIELDS), len(values)))\n'
    '        order_id = values[0].strip()\n'
    '        if not order_id:\n'
    '            raise FeedFormatError("row %d: empty order_id" % seq)\n'
    '        side = values[1].strip().upper()\n'
    '        if side not in ("BUY", "SELL"):\n'
    '            raise FeedFormatError("row %d: bad side %r" % (seq, values[1]))\n'
    '        instrument = values[2].strip()\n'
    '        try:\n'
    '            quantity = int(values[3].strip())\n'
    '            price = float(values[4].strip())\n'
    '        except ValueError:\n'
    '            raise FeedFormatError("row %d: bad quantity or price" % seq)\n'
    '        ts = parse_timestamp(values[5].strip())\n'
    '        return cls(order_id, side, instrument, quantity, price, ts, seq)\n'
    '\n'
    '    def gross(self):\n'
    '        return self.quantity * self.price\n'
    '\n'
    '    def as_dict(self):\n'
    '        return {\n'
    '            "seq": self.seq,\n'
    '            "side": self.side,\n'
    '            "instrument": self.instrument,\n'
    '            "quantity": self.quantity,\n'
    '            "price": self.price,\n'
    '            "timestamp": self.timestamp.isoformat(),\n'
    '        }\n'
    '\n'
    '\n'
    'def parse_timestamp(text):\n'
    '    try:\n'
    '        return datetime.strptime(text, "%Y-%m-%dT%H:%M:%S")\n'
    '    except ValueError:\n'
    '        raise FeedFormatError("bad timestamp %r" % text)\n',
    # v2 (commit 16): fractional seconds
    '"""Row-level model for a single fill record in an order feed."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'from .errors import FeedFormatError\n'
    '\n'
    'FIELDS = ("order_id", "side", "instrument", "quantity", "price", '
    '"timestamp")\n'
    'TS_FORMATS = ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S")\n'
    '\n'
    '\n'
    'class OrderRow:\n'
    '    """One fill row."""\n'
    '\n'
    '    __slots__ = ("order_id", "side", "instrument", "quantity", "price",\n'
    '                 "timestamp", "seq")\n'
    '\n'
    '    def __init__(self, order_id, side, instrument, quantity, price,\n'
    '                 timestamp, seq):\n'
    '        self.order_id = order_id\n'
    '        self.side = side\n'
    '        self.instrument = instrument\n'
    '        self.quantity = quantity\n'
    '        self.price = price\n'
    '        self.timestamp = timestamp\n'
    '        self.seq = seq\n'
    '\n'
    '    @classmethod\n'
    '    def from_fields(cls, values, seq):\n'
    '        """Build a row from raw CSV fields; bad rows raise '
    'FeedFormatError."""\n'
    '        if len(values) != len(FIELDS):\n'
    '            raise FeedFormatError("row %d: expected %d fields, got %d"\n'
    '                                   % (seq, len(FIELDS), len(values)))\n'
    '        order_id = values[0].strip()\n'
    '        if not order_id:\n'
    '            raise FeedFormatError("row %d: empty order_id" % seq)\n'
    '        side = values[1].strip().upper()\n'
    '        if side not in ("BUY", "SELL"):\n'
    '            raise FeedFormatError("row %d: bad side %r" % (seq, values[1]))\n'
    '        instrument = values[2].strip()\n'
    '        try:\n'
    '            quantity = int(values[3].strip())\n'
    '            price = float(values[4].strip())\n'
    '        except ValueError:\n'
    '            raise FeedFormatError("row %d: bad quantity or price" % seq)\n'
    '        ts = parse_timestamp(values[5].strip())\n'
    '        return cls(order_id, side, instrument, quantity, price, ts, seq)\n'
    '\n'
    '    def gross(self):\n'
    '        return self.quantity * self.price\n'
    '\n'
    '    def as_dict(self):\n'
    '        return {\n'
    '            "seq": self.seq,\n'
    '            "side": self.side,\n'
    '            "instrument": self.instrument,\n'
    '            "quantity": self.quantity,\n'
    '            "price": self.price,\n'
    '            "timestamp": self.timestamp.isoformat(),\n'
    '        }\n'
    '\n'
    '\n'
    'def parse_timestamp(text):\n'
    '    for fmt in TS_FORMATS:\n'
    '        try:\n'
    '            return datetime.strptime(text, fmt)\n'
    '        except ValueError:\n'
    '            continue\n'
    '    raise FeedFormatError("bad timestamp %r" % text)\n',
    # v3 (commit 25): precompiled regex
    '"""Row-level model for a single fill record in an order feed."""\n'
    '\n'
    'import re\n'
    'from datetime import datetime\n'
    '\n'
    'from .errors import FeedFormatError\n'
    '\n'
    'FIELDS = ("order_id", "side", "instrument", "quantity", "price", '
    '"timestamp")\n'
    'PACKED_TS = re.compile(\n'
    '    r"^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})'
    '(?:\\.(\\d{1,6}))?$")\n'
    '\n'
    '\n'
    'class OrderRow:\n'
    '    """One fill row. `seq` is the 1-based position of the fill among the\n'
    '    accepted rows of the feed."""\n'
    '\n'
    '    __slots__ = ("order_id", "side", "instrument", "quantity", "price",\n'
    '                 "timestamp", "seq")\n'
    '\n'
    '    def __init__(self, order_id, side, instrument, quantity, price,\n'
    '                 timestamp, seq):\n'
    '        self.order_id = order_id\n'
    '        self.side = side\n'
    '        self.instrument = instrument\n'
    '        self.quantity = quantity\n'
    '        self.price = price\n'
    '        self.timestamp = timestamp\n'
    '        self.seq = seq\n'
    '\n'
    '    @classmethod\n'
    '    def from_fields(cls, values, seq):\n'
    '        """Build a row from raw CSV fields; bad rows raise '
    'FeedFormatError."""\n'
    '        if len(values) != len(FIELDS):\n'
    '            raise FeedFormatError("row %d: expected %d fields, got %d"\n'
    '                                   % (seq, len(FIELDS), len(values)))\n'
    '        order_id = values[0].strip()\n'
    '        if not order_id:\n'
    '            raise FeedFormatError("row %d: empty order_id" % seq)\n'
    '        side = values[1].strip().upper()\n'
    '        if side not in ("BUY", "SELL"):\n'
    '            raise FeedFormatError("row %d: bad side %r" % (seq, values[1]))\n'
    '        instrument = values[2].strip()\n'
    '        try:\n'
    '            quantity = int(values[3].strip())\n'
    '            price = float(values[4].strip())\n'
    '        except ValueError:\n'
    '            raise FeedFormatError("row %d: bad quantity or price" % seq)\n'
    '        ts = parse_timestamp(values[5].strip())\n'
    '        return cls(order_id, side, instrument, quantity, price, ts, seq)\n'
    '\n'
    '    def gross(self):\n'
    '        return self.quantity * self.price\n'
    '\n'
    '    def as_dict(self):\n'
    '        return {\n'
    '            "seq": self.seq,\n'
    '            "side": self.side,\n'
    '            "instrument": self.instrument,\n'
    '            "quantity": self.quantity,\n'
    '            "price": self.price,\n'
    '            "timestamp": self.timestamp.isoformat(),\n'
    '        }\n'
    '\n'
    '\n'
    'def parse_timestamp(text):\n'
    '    m = PACKED_TS.match(text)\n'
    '    if not m:\n'
    '        raise FeedFormatError("bad timestamp %r" % text)\n'
    '    year, month, day, hour, minute, second = (int(g) for g in '
    'm.groups()[:6])\n'
    '    frac = m.group(7)\n'
    '    micro = int(frac.ljust(6, "0")) if frac else 0\n'
    '    try:\n'
    '        return datetime(year, month, day, hour, minute, second, micro)\n'
    '    except ValueError as exc:\n'
    '        raise FeedFormatError("bad timestamp %r: %s" % (text, exc))\n',
    # v4 (commit 33): split conversion helpers
    '"""Row-level model for a single fill record in an order feed."""\n'
    '\n'
    'import re\n'
    'from datetime import datetime\n'
    '\n'
    'from .errors import FeedFormatError\n'
    '\n'
    'FIELDS = ("order_id", "side", "instrument", "quantity", "price", '
    '"timestamp")\n'
    'PACKED_TS = re.compile(\n'
    '    r"^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})'
    '(?:\\.(\\d{1,6}))?$")\n'
    '\n'
    '\n'
    'def _required_text(values, index, label, seq):\n'
    '    text = values[index].strip()\n'
    '    if not text:\n'
    '        raise FeedFormatError("row %d: empty %s" % (seq, label))\n'
    '    return text\n'
    '\n'
    '\n'
    'def _to_quantity(text, seq):\n'
    '    try:\n'
    '        return int(text.strip())\n'
    '    except ValueError:\n'
    '        raise FeedFormatError("row %d: bad quantity %r" % (seq, text))\n'
    '\n'
    '\n'
    'def _to_price(text, seq):\n'
    '    try:\n'
    '        return float(text.strip())\n'
    '    except ValueError:\n'
    '        raise FeedFormatError("row %d: bad price %r" % (seq, text))\n'
    '\n'
    '\n'
    'def parse_timestamp(text):\n'
    '    m = PACKED_TS.match(text)\n'
    '    if not m:\n'
    '        raise FeedFormatError("bad timestamp %r" % text)\n'
    '    year, month, day, hour, minute, second = (int(g) for g in '
    'm.groups()[:6])\n'
    '    frac = m.group(7)\n'
    '    micro = int(frac.ljust(6, "0")) if frac else 0\n'
    '    try:\n'
    '        return datetime(year, month, day, hour, minute, second, micro)\n'
    '    except ValueError as exc:\n'
    '        raise FeedFormatError("bad timestamp %r: %s" % (text, exc))\n'
    '\n'
    '\n'
    'class OrderRow:\n'
    '    """One fill row. `seq` is the 1-based position of the fill among the\n'
    '    accepted rows of the feed."""\n'
    '\n'
    '    __slots__ = ("order_id", "side", "instrument", "quantity", "price",\n'
    '                 "timestamp", "seq")\n'
    '\n'
    '    def __init__(self, order_id, side, instrument, quantity, price,\n'
    '                 timestamp, seq):\n'
    '        self.order_id = order_id\n'
    '        self.side = side\n'
    '        self.instrument = instrument\n'
    '        self.quantity = quantity\n'
    '        self.price = price\n'
    '        self.timestamp = timestamp\n'
    '        self.seq = seq\n'
    '\n'
    '    @classmethod\n'
    '    def from_fields(cls, values, seq):\n'
    '        """Build a row from raw CSV fields; bad rows raise '
    'FeedFormatError."""\n'
    '        if len(values) != len(FIELDS):\n'
    '            raise FeedFormatError("row %d: expected %d fields, got %d"\n'
    '                                   % (seq, len(FIELDS), len(values)))\n'
    '        order_id = _required_text(values, 0, "order_id", seq)\n'
    '        side = _required_text(values, 1, "side", seq).upper()\n'
    '        if side not in ("BUY", "SELL"):\n'
    '            raise FeedFormatError("row %d: bad side %r" % (seq, values[1]))\n'
    '        instrument = _required_text(values, 2, "instrument", seq)\n'
    '        quantity = _to_quantity(values[3], seq)\n'
    '        price = _to_price(values[4], seq)\n'
    '        ts = parse_timestamp(values[5].strip())\n'
    '        return cls(order_id, side, instrument, quantity, price, ts, seq)\n'
    '\n'
    '    def gross(self):\n'
    '        return self.quantity * self.price\n'
    '\n'
    '    def as_dict(self):\n'
    '        return {\n'
    '            "seq": self.seq,\n'
    '            "side": self.side,\n'
    '            "instrument": self.instrument,\n'
    '            "quantity": self.quantity,\n'
    '            "price": self.price,\n'
    '            "timestamp": self.timestamp.isoformat(),\n'
    '        }\n',
]

CONTENT["conduit/feeds.py"] = [
    # v1 (commit 3)
    '"""Feed parsing: recognise the vendor dialect and yield OrderRow '
    'objects."""\n'
    '\n'
    'import csv\n'
    'import io\n'
    '\n'
    'from .errors import FeedFormatError\n'
    'from .orders import FIELDS, OrderRow\n'
    '\n'
    '\n'
    'def parse_feed(text):\n'
    '    """Parse feed text into (rows, warnings) with feed order preserved.\n'
    '\n'
    '    Structural failures raise FeedFormatError; individual bad rows are\n'
    '    skipped and reported as warnings instead of aborting the run.\n'
    '    """\n'
    '    reader = csv.reader(io.StringIO(text))\n'
    '    try:\n'
    '        header = next(reader)\n'
    '    except StopIteration:\n'
    '        raise FeedFormatError("empty feed")\n'
    '    if [h.strip().lower() for h in header] != list(FIELDS):\n'
    '        raise FeedFormatError("unexpected header %r" % header)\n'
    '    rows = []\n'
    '    warnings = []\n'
    '    for lineno, record in enumerate(reader, start=2):\n'
    '        try:\n'
    '            rows.append(OrderRow.from_fields(record, len(rows) + 1))\n'
    '        except FeedFormatError as exc:\n'
    '            warnings.append({"line": lineno, "message": str(exc)})\n'
    '    if not rows:\n'
    '        raise FeedFormatError("feed contains no rows")\n'
    '    return rows, warnings\n',
    # v2 (commit 13): wire semantic validation in
    '"""Feed parsing: recognise the vendor dialect and yield OrderRow '
    'objects."""\n'
    '\n'
    'import csv\n'
    'import io\n'
    '\n'
    'from .errors import FeedFormatError, FieldValidationError\n'
    'from .orders import FIELDS, OrderRow\n'
    'from .validate import check_row\n'
    '\n'
    '\n'
    'def parse_feed(text):\n'
    '    """Parse feed text into (rows, warnings) with feed order preserved.\n'
    '\n'
    '    Structural failures raise FeedFormatError; individual bad rows are\n'
    '    skipped and reported as warnings instead of aborting the run.\n'
    '    """\n'
    '    reader = csv.reader(io.StringIO(text), skipinitialspace=True)\n'
    '    try:\n'
    '        header = next(reader)\n'
    '    except StopIteration:\n'
    '        raise FeedFormatError("empty feed")\n'
    '    if [h.strip().lower() for h in header] != list(FIELDS):\n'
    '        raise FeedFormatError("unexpected header %r" % header)\n'
    '    rows = []\n'
    '    warnings = []\n'
    '    for lineno, record in enumerate(reader, start=2):\n'
    '        try:\n'
    '            row = OrderRow.from_fields(record, len(rows) + 1)\n'
    '            check_row(row)\n'
    '        except (FeedFormatError, FieldValidationError) as exc:\n'
    '            warnings.append({"line": lineno, "message": str(exc)})\n'
    '            continue\n'
    '        rows.append(row)\n'
    '    if not rows:\n'
    '        raise FeedFormatError("feed contains no rows")\n'
    '    return rows, warnings\n',
    # v3 (commit 31): BOM + blank lines
    '"""Feed parsing: recognise the vendor dialect and yield OrderRow '
    'objects."""\n'
    '\n'
    'import csv\n'
    'import io\n'
    '\n'
    'from .errors import FeedFormatError, FieldValidationError\n'
    'from .orders import FIELDS, OrderRow\n'
    'from .validate import check_row\n'
    '\n'
    '\n'
    'def parse_feed(text):\n'
    '    """Parse feed text into (rows, warnings) with feed order preserved.\n'
    '\n'
    '    Structural failures raise FeedFormatError; individual bad rows are\n'
    '    skipped and reported as warnings instead of aborting the run. A\n'
    '    leading BOM and fully blank lines are tolerated.\n'
    '    """\n'
    '    text = text.lstrip("\\ufeff")\n'
    '    reader = csv.reader(io.StringIO(text), skipinitialspace=True)\n'
    '    try:\n'
    '        header = next(reader)\n'
    '    except StopIteration:\n'
    '        raise FeedFormatError("empty feed")\n'
    '    if [h.strip().lower() for h in header] != list(FIELDS):\n'
    '        raise FeedFormatError("unexpected header %r" % header)\n'
    '    rows = []\n'
    '    warnings = []\n'
    '    for lineno, record in enumerate(reader, start=2):\n'
    '        if not record or not any(cell.strip() for cell in record):\n'
    '            continue\n'
    '        try:\n'
    '            row = OrderRow.from_fields(record, len(rows) + 1)\n'
    '            check_row(row)\n'
    '        except (FeedFormatError, FieldValidationError) as exc:\n'
    '            warnings.append({"line": lineno, "message": str(exc)})\n'
    '            continue\n'
    '        rows.append(row)\n'
    '    if not rows:\n'
    '        raise FeedFormatError("feed contains no rows")\n'
    '    return rows, warnings\n',
]

CONTENT["conduit/validate.py"] = [
    # v1 (commit 13)
    '"""Semantic (range) validation for parsed rows."""\n'
    '\n'
    'from .errors import FieldValidationError\n'
    '\n'
    '\n'
    'def check_row(row):\n'
    '    """Raise FieldValidationError when a row violates a semantic rule."""\n'
    '    if row.quantity <= 0:\n'
    '        raise FieldValidationError("quantity must be a positive integer")\n'
    '    if row.price <= 0:\n'
    '        raise FieldValidationError("price must be a positive number")\n',
    # v2 (commit 23): symbol rule
    '"""Semantic (range and format) validation for parsed rows."""\n'
    '\n'
    'import re\n'
    '\n'
    'from .errors import FieldValidationError\n'
    '\n'
    'INSTRUMENT_RE = re.compile(r"^[A-Z0-9][A-Z0-9-]*$")\n'
    '\n'
    '\n'
    'def check_row(row):\n'
    '    """Raise FieldValidationError when a row violates a semantic rule."""\n'
    '    if row.quantity <= 0:\n'
    '        raise FieldValidationError("quantity must be a positive integer")\n'
    '    if row.price <= 0:\n'
    '        raise FieldValidationError("price must be a positive number")\n'
    '    if not INSTRUMENT_RE.match(row.instrument):\n'
    '        raise FieldValidationError(\n'
    '            "instrument must be uppercase alphanumeric (dashes allowed)")\n',
]

CONTENT["conduit/aggregate.py"] = [
    # v1 (commit 4)
    '"""Group feed rows into orders and compute the order summary fields."""\n'
    '\n'
    'FEE_RATE = 0.0015\n'
    '\n'
    '\n'
    'def group_rows(rows):\n'
    '    """Group rows into orders, preserving the order of first appearance.\n'
    '\n'
    '    A feed may carry several rows with the same order id: basket orders\n'
    '    are split into one row per fill and every fill must survive into the\n'
    '    order\'s fill list.\n'
    '    """\n'
    '    groups = {}\n'
    '    order_of = []\n'
    '    for row in rows:\n'
    '        if row.order_id not in groups:\n'
    '            groups[row.order_id] = []\n'
    '            order_of.append(row.order_id)\n'
    '        groups[row.order_id].append(row)\n'
    '    return [(oid, groups[oid]) for oid in order_of]\n'
    '\n'
    '\n'
    'def summarize(orders, fee_rate=FEE_RATE):\n'
    '    """Compute the canonical order objects (gross, fee, net, sides)."""\n'
    '    out = []\n'
    '    for oid, fills in orders:\n'
    '        gross = round(sum(f.gross() for f in fills), 2)\n'
    '        fee = round(gross * fee_rate, 2)\n'
    '        net = round(gross - fee, 2)\n'
    '        sides = []\n'
    '        for f in fills:\n'
    '            if f.side not in sides:\n'
    '                sides.append(f.side)\n'
    '        out.append({"order_id": oid,\n'
    '                    "fills": [f.as_dict() for f in fills],\n'
    '                    "fill_count": len(fills),\n'
    '                    "gross": gross,\n'
    '                    "fee": fee,\n'
    '                    "net": net,\n'
    '                    "sides": sides})\n'
    '    return out\n',
    # v2 (commit 20): canonical fill ordering
    '"""Group feed rows into orders and compute the order summary fields."""\n'
    '\n'
    'FEE_RATE = 0.0015\n'
    '\n'
    '\n'
    'def group_rows(rows):\n'
    '    """Group rows into orders, preserving the order of first appearance.\n'
    '\n'
    '    A feed may carry several rows with the same order id: basket orders\n'
    '    are split into one row per fill and every fill must survive into the\n'
    '    order\'s fill list. Fills are ordered by timestamp, ties broken by\n'
    '    feed position (seq).\n'
    '    """\n'
    '    groups = {}\n'
    '    order_of = []\n'
    '    for row in rows:\n'
    '        if row.order_id not in groups:\n'
    '            groups[row.order_id] = []\n'
    '            order_of.append(row.order_id)\n'
    '        groups[row.order_id].append(row)\n'
    '    orders = []\n'
    '    for oid in order_of:\n'
    '        fills = sorted(groups[oid], key=lambda r: (r.timestamp, r.seq))\n'
    '        orders.append((oid, fills))\n'
    '    return orders\n'
    '\n'
    '\n'
    'def summarize(orders, fee_rate=FEE_RATE):\n'
    '    """Compute the canonical order objects (gross, fee, net, sides)."""\n'
    '    out = []\n'
    '    for oid, fills in orders:\n'
    '        gross = round(sum(f.gross() for f in fills), 2)\n'
    '        fee = round(gross * fee_rate, 2)\n'
    '        net = round(gross - fee, 2)\n'
    '        sides = []\n'
    '        for f in fills:\n'
    '            if f.side not in sides:\n'
    '                sides.append(f.side)\n'
    '        out.append({"order_id": oid,\n'
    '                    "fills": [f.as_dict() for f in fills],\n'
    '                    "fill_count": len(fills),\n'
    '                    "gross": gross,\n'
    '                    "fee": fee,\n'
    '                    "net": net,\n'
    '                    "sides": sides})\n'
    '    return out\n',
    # v3 (commit 26): THE REGRESSION - collapse duplicate order rows
    '"""Group feed rows into orders and compute the order summary fields."""\n'
    '\n'
    'FEE_RATE = 0.0015\n'
    '\n'
    '\n'
    'def group_rows(rows):\n'
    '    """Group rows into orders.\n'
    '\n'
    '    The vendor feed repeats the order id on every fill, so the serialised\n'
    '    rows carry many duplicates of the same order envelope. Collapse the\n'
    '    repeats and emit one representative fill per order; ordering follows\n'
    '    the fill timestamps of the surviving rows.\n'
    '    """\n'
    '    collapsed = {}\n'
    '    for row in rows:\n'
    '        collapsed[row.order_id] = row\n'
    '    reps = sorted(collapsed.values(), key=lambda r: (r.timestamp, r.seq))\n'
    '    return [(rep.order_id, [rep]) for rep in reps]\n'
    '\n'
    '\n'
    'def summarize(orders, fee_rate=FEE_RATE):\n'
    '    """Compute the canonical order objects (gross, fee, net, sides)."""\n'
    '    out = []\n'
    '    for oid, fills in orders:\n'
    '        gross = round(sum(f.gross() for f in fills), 2)\n'
    '        fee = round(gross * fee_rate, 2)\n'
    '        net = round(gross - fee, 2)\n'
    '        sides = []\n'
    '        for f in fills:\n'
    '            if f.side not in sides:\n'
    '                sides.append(f.side)\n'
    '        out.append({"order_id": oid,\n'
    '                    "fills": [f.as_dict() for f in fills],\n'
    '                    "fill_count": len(fills),\n'
    '                    "gross": gross,\n'
    '                    "fee": fee,\n'
    '                    "net": net,\n'
    '                    "sides": sides})\n'
    '    return out\n',
]

CONTENT["conduit/format.py"] = [
    # v1 (commit 5)
    '"""Canonical JSON rendering for order summaries."""\n'
    '\n'
    'import json\n'
    '\n'
    'RENDER_ORDER = ("order_id", "fills", "fill_count", "gross")\n'
    '\n'
    '\n'
    'def render(orders, warnings):\n'
    '    """Render the canonical document as UTF-8 bytes.\n'
    '\n'
    '    Field order inside each order object is fixed. Floats use Python\'s\n'
    '    repr. The document ends with a single newline.\n'
    '    """\n'
    '    trimmed = []\n'
    '    for order in orders:\n'
    '        trimmed.append({key: order[key] for key in RENDER_ORDER})\n'
    '    return (json.dumps({"orders": trimmed, "warnings": warnings},\n'
    '                       indent=2) + "\\n").encode("utf-8")\n',
    # v2 (commit 19): render fee/net/sides
    '"""Canonical JSON rendering for order summaries."""\n'
    '\n'
    'import json\n'
    '\n'
    'RENDER_ORDER = ("order_id", "fills", "fill_count", "gross", "fee",\n'
    '                "net", "sides")\n'
    '\n'
    '\n'
    'def render(orders, warnings):\n'
    '    """Render the canonical document as UTF-8 bytes.\n'
    '\n'
    '    Field order inside each order object is fixed. Floats use Python\'s\n'
    '    repr. The document ends with a single newline.\n'
    '    """\n'
    '    trimmed = []\n'
    '    for order in orders:\n'
    '        trimmed.append({key: order[key] for key in RENDER_ORDER})\n'
    '    return (json.dumps({"orders": trimmed, "warnings": warnings},\n'
    '                       indent=2) + "\\n").encode("utf-8")\n',
]

CONTENT["conduit/cli.py"] = [
    # v1 (commit 6)
    '"""Command-line entry point for conduit."""\n'
    '\n'
    'import argparse\n'
    'import sys\n'
    '\n'
    'from .aggregate import group_rows, summarize\n'
    'from .feeds import parse_feed\n'
    'from .format import render\n'
    '\n'
    '\n'
    'def process(feed_path, out_path):\n'
    '    with open(feed_path, "r", encoding="utf-8") as fh:\n'
    '        text = fh.read()\n'
    '    rows, warnings = parse_feed(text)\n'
    '    orders = summarize(group_rows(rows))\n'
    '    with open(out_path, "wb") as fh:\n'
    '        fh.write(render(orders, warnings))\n'
    '    return len(rows)\n'
    '\n'
    '\n'
    'def main(argv=None):\n'
    '    parser = argparse.ArgumentParser(\n'
    '        prog="conduit",\n'
    '        description="Normalise Tarn order feeds into canonical order '
    'summaries.")\n'
    '    parser.add_argument("feed", help="input feed CSV")\n'
    '    parser.add_argument("out", help="output canonical JSON document")\n'
    '    args = parser.parse_args(argv)\n'
    '    try:\n'
    '        process(args.feed, args.out)\n'
    '    except Exception as exc:\n'
    '        print("conduit: %s" % exc, file=sys.stderr)\n'
    '        return 2\n'
    '    return 0\n'
    '\n'
    '\n'
    'if __name__ == "__main__":\n'
    '    sys.exit(main())\n',
    # v2 (commit 18): report fill count on stderr
    '"""Command-line entry point for conduit."""\n'
    '\n'
    'import argparse\n'
    'import sys\n'
    '\n'
    'from .aggregate import group_rows, summarize\n'
    'from .feeds import parse_feed\n'
    'from .format import render\n'
    '\n'
    '\n'
    'def process(feed_path, out_path):\n'
    '    with open(feed_path, "r", encoding="utf-8") as fh:\n'
    '        text = fh.read()\n'
    '    rows, warnings = parse_feed(text)\n'
    '    orders = summarize(group_rows(rows))\n'
    '    with open(out_path, "wb") as fh:\n'
    '        fh.write(render(orders, warnings))\n'
    '    return len(rows)\n'
    '\n'
    '\n'
    'def main(argv=None):\n'
    '    parser = argparse.ArgumentParser(\n'
    '        prog="conduit",\n'
    '        description="Normalise Tarn order feeds into canonical order '
    'summaries.")\n'
    '    parser.add_argument("feed", help="input feed CSV")\n'
    '    parser.add_argument("out", help="output canonical JSON document")\n'
    '    args = parser.parse_args(argv)\n'
    '    try:\n'
    '        count = process(args.feed, args.out)\n'
    '    except Exception as exc:\n'
    '        print("conduit: %s" % exc, file=sys.stderr)\n'
    '        return 2\n'
    '    print("conduit: wrote %d fills to %s" % (count, args.out),\n'
    '          file=sys.stderr)\n'
    '    return 0\n'
    '\n'
    '\n'
    'if __name__ == "__main__":\n'
    '    sys.exit(main())\n',
    # v3 (commit 27): stdin support
    '"""Command-line entry point for conduit."""\n'
    '\n'
    'import argparse\n'
    'import sys\n'
    '\n'
    'from .aggregate import group_rows, summarize\n'
    'from .feeds import parse_feed\n'
    'from .format import render\n'
    '\n'
    '\n'
    'def _read_feed(feed_path):\n'
    '    if feed_path == "-":\n'
    '        return sys.stdin.read()\n'
    '    with open(feed_path, "r", encoding="utf-8") as fh:\n'
    '        return fh.read()\n'
    '\n'
    '\n'
    'def process(feed_path, out_path):\n'
    '    text = _read_feed(feed_path)\n'
    '    rows, warnings = parse_feed(text)\n'
    '    orders = summarize(group_rows(rows))\n'
    '    with open(out_path, "wb") as fh:\n'
    '        fh.write(render(orders, warnings))\n'
    '    return len(rows)\n'
    '\n'
    '\n'
    'def main(argv=None):\n'
    '    parser = argparse.ArgumentParser(\n'
    '        prog="conduit",\n'
    '        description="Normalise Tarn order feeds into canonical order '
    'summaries.")\n'
    '    parser.add_argument("feed", help="input feed CSV (\'-\' for stdin)")\n'
    '    parser.add_argument("out", help="output canonical JSON document")\n'
    '    args = parser.parse_args(argv)\n'
    '    try:\n'
    '        count = process(args.feed, args.out)\n'
    '    except Exception as exc:\n'
    '        print("conduit: %s" % exc, file=sys.stderr)\n'
    '        return 2\n'
    '    print("conduit: wrote %d fills to %s" % (count, args.out),\n'
    '          file=sys.stderr)\n'
    '    return 0\n'
    '\n'
    '\n'
    'if __name__ == "__main__":\n'
    '    sys.exit(main())\n',
]

CONTENT["conduit/__main__.py"] = [
    '"""Allow `python3 -m conduit`."""\n'
    '\n'
    'import sys\n'
    '\n'
    'from .cli import main\n'
    '\n'
    'if __name__ == "__main__":\n'
    '    sys.exit(main())\n',
]

CONTENT["tests/conftest.py"] = [
    'import os\n'
    'import sys\n'
    '\n'
    '# Make the repository root importable regardless of how pytest is invoked.\n'
    'sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))\n',
]

CONTENT["tests/test_feeds.py"] = [
    # v1 (commit 7)
    '"""Tests for feed parsing."""\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.feeds import parse_feed\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_empty_feed_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("")\n'
    '\n'
    '\n'
    'def test_bad_header_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("order_id,side,instrument,quantity,price\\n")\n'
    '\n'
    '\n'
    'def test_single_row_parses():\n'
    '    rows, warnings = parse_feed(\n'
    '        HEADER + "A-1,BUY,TARNCORP,100,12.50,2025-01-02T09:00:01\\n")\n'
    '    assert warnings == []\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-1"\n'
    '    assert rows[0].quantity == 100\n'
    '    assert rows[0].gross() == 1250.0\n'
    '\n'
    '\n'
    'def test_bad_side_is_a_warning():\n'
    '    feed = (HEADER\n'
    '            + "A-2,UP,TARNCORP,10,1.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-3,SELL,ORNX,5,2.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-3"\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n',
    # v2 (commit 15): dialect tolerance
    '"""Tests for feed parsing."""\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.feeds import parse_feed\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_empty_feed_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("")\n'
    '\n'
    '\n'
    'def test_bad_header_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("order_id,side,instrument,quantity,price\\n")\n'
    '\n'
    '\n'
    'def test_single_row_parses():\n'
    '    rows, warnings = parse_feed(\n'
    '        HEADER + "A-1,BUY,TARNCORP,100,12.50,2025-01-02T09:00:01\\n")\n'
    '    assert warnings == []\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-1"\n'
    '    assert rows[0].quantity == 100\n'
    '    assert rows[0].gross() == 1250.0\n'
    '\n'
    '\n'
    'def test_bad_side_is_a_warning():\n'
    '    feed = (HEADER\n'
    '            + "A-2,UP,TARNCORP,10,1.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-3,SELL,ORNX,5,2.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-3"\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '\n'
    '\n'
    'def test_spacey_header_and_crlf():\n'
    '    feed = ("order_id, side, instrument, quantity, price, timestamp\\r\\n"\n'
    '            + "A-9,BUY,TARNCORP,3,4.50,2025-01-02T09:00:01\\r\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert warnings == []\n'
    '    assert rows[0].quantity == 3\n',
    # v3 (commit 32): BOM + blank lines
    '"""Tests for feed parsing."""\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.feeds import parse_feed\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_empty_feed_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("")\n'
    '\n'
    '\n'
    'def test_bad_header_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        parse_feed("order_id,side,instrument,quantity,price\\n")\n'
    '\n'
    '\n'
    'def test_single_row_parses():\n'
    '    rows, warnings = parse_feed(\n'
    '        HEADER + "A-1,BUY,TARNCORP,100,12.50,2025-01-02T09:00:01\\n")\n'
    '    assert warnings == []\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-1"\n'
    '    assert rows[0].quantity == 100\n'
    '    assert rows[0].gross() == 1250.0\n'
    '\n'
    '\n'
    'def test_bad_side_is_a_warning():\n'
    '    feed = (HEADER\n'
    '            + "A-2,UP,TARNCORP,10,1.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-3,SELL,ORNX,5,2.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert rows[0].order_id == "A-3"\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '\n'
    '\n'
    'def test_spacey_header_and_crlf():\n'
    '    feed = ("order_id, side, instrument, quantity, price, timestamp\\r\\n"\n'
    '            + "A-9,BUY,TARNCORP,3,4.50,2025-01-02T09:00:01\\r\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert warnings == []\n'
    '    assert rows[0].quantity == 3\n'
    '\n'
    '\n'
    'def test_leading_bom_is_tolerated():\n'
    '    feed = "\\ufeff" + HEADER + "A-5,BUY,TARNCORP,2,9.25,2025-01-02T09:00:01\\n"\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert warnings == []\n'
    '\n'
    '\n'
    'def test_blank_lines_are_skipped():\n'
    '    feed = (HEADER + "\\n"\n'
    '            + "A-6,BUY,ORNX,1,1.00,2025-01-02T09:00:01\\n\\n"\n'
    '            + "A-7,SELL,ORNX,2,1.10,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 2\n'
    '    assert warnings == []\n',
]

CONTENT["tests/test_orders.py"] = [
    # v1 (commit 8)
    '"""Tests for the OrderRow model."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.orders import OrderRow\n'
    '\n'
    '\n'
    'def test_from_fields_orders_fields():\n'
    '    row = OrderRow.from_fields(\n'
    '        ["A-1", "buy", "tarncorp", "100", "12.50", "2025-01-02T09:00:01"], 1)\n'
    '    assert row.order_id == "A-1"\n'
    '    assert row.side == "BUY"\n'
    '    assert row.instrument == "tarncorp"\n'
    '    assert row.quantity == 100\n'
    '    assert row.price == 12.50\n'
    '    assert row.timestamp == datetime(2025, 1, 2, 9, 0, 1)\n'
    '    assert row.seq == 1\n'
    '\n'
    '\n'
    'def test_gross():\n'
    '    row = OrderRow("X", "BUY", "I", 150, 12.40,\n'
    '                   datetime(2025, 1, 2, 9, 0, 0), 1)\n'
    '    assert row.gross() == 1860.0\n'
    '\n'
    '\n'
    'def test_bad_quantity_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-2", "BUY", "I", "abc", "1.0", "2025-01-02T09:00:01"], 2)\n'
    '\n'
    '\n'
    'def test_bad_timestamp_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-3", "BUY", "I", "1", "1.0", "yesterday"], 3)\n',
    # v2 (commit 17)
    '"""Tests for the OrderRow model."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.orders import OrderRow\n'
    '\n'
    '\n'
    'def test_from_fields_orders_fields():\n'
    '    row = OrderRow.from_fields(\n'
    '        ["A-1", "buy", "tarncorp", "100", "12.50", "2025-01-02T09:00:01"], 1)\n'
    '    assert row.order_id == "A-1"\n'
    '    assert row.side == "BUY"\n'
    '    assert row.instrument == "tarncorp"\n'
    '    assert row.quantity == 100\n'
    '    assert row.price == 12.50\n'
    '    assert row.timestamp == datetime(2025, 1, 2, 9, 0, 1)\n'
    '    assert row.seq == 1\n'
    '\n'
    '\n'
    'def test_gross():\n'
    '    row = OrderRow("X", "BUY", "I", 150, 12.40,\n'
    '                   datetime(2025, 1, 2, 9, 0, 0), 1)\n'
    '    assert row.gross() == 1860.0\n'
    '\n'
    '\n'
    'def test_fractional_seconds():\n'
    '    row = OrderRow.from_fields(\n'
    '        ["A-9", "BUY", "TARNCORP", "1", "1.00", "2025-01-02T09:00:01.125000"], 1)\n'
    '    assert row.timestamp.microsecond == 125000\n'
    '\n'
    '\n'
    'def test_bad_quantity_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-2", "BUY", "I", "abc", "1.0", "2025-01-02T09:00:01"], 2)\n'
    '\n'
    '\n'
    'def test_bad_timestamp_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-3", "BUY", "I", "1", "1.0", "yesterday"], 3)\n',
    # v3 (commit 34)
    '"""Tests for the OrderRow model."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'import pytest\n'
    '\n'
    'from conduit.errors import FeedFormatError\n'
    'from conduit.orders import OrderRow\n'
    '\n'
    '\n'
    'def test_from_fields_orders_fields():\n'
    '    row = OrderRow.from_fields(\n'
    '        ["A-1", "buy", "tarncorp", "100", "12.50", "2025-01-02T09:00:01"], 1)\n'
    '    assert row.order_id == "A-1"\n'
    '    assert row.side == "BUY"\n'
    '    assert row.instrument == "tarncorp"\n'
    '    assert row.quantity == 100\n'
    '    assert row.price == 12.50\n'
    '    assert row.timestamp == datetime(2025, 1, 2, 9, 0, 1)\n'
    '    assert row.seq == 1\n'
    '\n'
    '\n'
    'def test_gross():\n'
    '    row = OrderRow("X", "BUY", "I", 150, 12.40,\n'
    '                   datetime(2025, 1, 2, 9, 0, 0), 1)\n'
    '    assert row.gross() == 1860.0\n'
    '\n'
    '\n'
    'def test_fractional_seconds():\n'
    '    row = OrderRow.from_fields(\n'
    '        ["A-9", "BUY", "TARNCORP", "1", "1.00", "2025-01-02T09:00:01.125000"], 1)\n'
    '    assert row.timestamp.microsecond == 125000\n'
    '\n'
    '\n'
    'def test_bad_quantity_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-2", "BUY", "I", "abc", "1.0", "2025-01-02T09:00:01"], 2)\n'
    '\n'
    '\n'
    'def test_bad_timestamp_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(\n'
    '            ["A-3", "BUY", "I", "1", "1.0", "yesterday"], 3)\n'
    '\n'
    '\n'
    'def test_short_row_raises():\n'
    '    with pytest.raises(FeedFormatError):\n'
    '        OrderRow.from_fields(["A-4", "BUY"], 4)\n',
]

CONTENT["tests/test_aggregate.py"] = [
    # v1 (commit 9)
    '"""Tests for order aggregation."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'from conduit.aggregate import group_rows, summarize\n'
    'from conduit.orders import OrderRow\n'
    '\n'
    '\n'
    'def _row(oid, side, qty, price, ts, seq):\n'
    '    return OrderRow(oid, side, "TARNCORP", qty, price,\n'
    '                    datetime.fromisoformat(ts), seq)\n'
    '\n'
    '\n'
    'def test_single_fill_envelope():\n'
    '    orders = group_rows(\n'
    '        [_row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:01", 1)])\n'
    '    assert len(orders) == 1\n'
    '    oid, fills = orders[0]\n'
    '    assert oid == "O-1"\n'
    '    assert len(fills) == 1\n'
    '    assert fills[0].quantity == 100\n'
    '\n'
    '\n'
    'def test_multiple_orders_keep_appearance_order():\n'
    '    rows = [\n'
    '        _row("O-2", "SELL", 5, 2.00, "2025-01-02T09:00:01", 1),\n'
    '        _row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:02", 2),\n'
    '    ]\n'
    '    orders = group_rows(rows)\n'
    '    assert [oid for oid, _ in orders] == ["O-2", "O-1"]\n'
    '\n'
    '\n'
    'def test_summarize_totals():\n'
    '    orders = summarize([\n'
    '        ("O-1", [_row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:01", 1)])])\n'
    '    order = orders[0]\n'
    '    assert order["fill_count"] == 1\n'
    '    assert order["gross"] == 1250.0\n'
    '    assert order["sides"] == ["BUY"]\n',
    # v2 (commit 21)
    '"""Tests for order aggregation."""\n'
    '\n'
    'from datetime import datetime\n'
    '\n'
    'from conduit.aggregate import group_rows, summarize\n'
    'from conduit.orders import OrderRow\n'
    '\n'
    '\n'
    'def _row(oid, side, qty, price, ts, seq):\n'
    '    return OrderRow(oid, side, "TARNCORP", qty, price,\n'
    '                    datetime.fromisoformat(ts), seq)\n'
    '\n'
    '\n'
    'def test_single_fill_envelope():\n'
    '    orders = group_rows(\n'
    '        [_row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:01", 1)])\n'
    '    assert len(orders) == 1\n'
    '    oid, fills = orders[0]\n'
    '    assert oid == "O-1"\n'
    '    assert len(fills) == 1\n'
    '    assert fills[0].quantity == 100\n'
    '\n'
    '\n'
    'def test_multiple_orders_keep_appearance_order():\n'
    '    rows = [\n'
    '        _row("O-2", "SELL", 5, 2.00, "2025-01-02T09:00:01", 1),\n'
    '        _row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:02", 2),\n'
    '    ]\n'
    '    orders = group_rows(rows)\n'
    '    assert [oid for oid, _ in orders] == ["O-2", "O-1"]\n'
    '\n'
    '\n'
    'def test_timestamp_ties_break_by_feed_position():\n'
    '    rows = [\n'
    '        _row("O-2", "SELL", 5, 2.00, "2025-01-02T09:00:00", 1),\n'
    '        _row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:00", 2),\n'
    '    ]\n'
    '    orders = group_rows(rows)\n'
    '    assert [oid for oid, _ in orders] == ["O-2", "O-1"]\n'
    '\n'
    '\n'
    'def test_summarize_totals():\n'
    '    orders = summarize([\n'
    '        ("O-1", [_row("O-1", "BUY", 100, 12.50, "2025-01-02T09:00:01", 1)])])\n'
    '    order = orders[0]\n'
    '    assert order["fill_count"] == 1\n'
    '    assert order["gross"] == 1250.0\n'
    '    assert order["sides"] == ["BUY"]\n',
]

CONTENT["tests/test_validate.py"] = [
    # v1 (commit 14)
    '"""Tests for semantic validation wired into feed parsing."""\n'
    '\n'
    'from conduit.feeds import parse_feed\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_negative_quantity_warns():\n'
    '    feed = (HEADER\n'
    '            + "A-1,BUY,TARNCORP,-5,10.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-2,SELL,ORNX,5,10.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '    assert "quantity" in warnings[0]["message"]\n'
    '\n'
    '\n'
    'def test_zero_price_warns():\n'
    '    feed = (HEADER\n'
    '            + "A-3,BUY,TARNCORP,5,0.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-4,SELL,ORNX,5,10.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '    assert "price" in warnings[0]["message"]\n',
    # v2 (commit 24)
    '"""Tests for semantic validation wired into feed parsing."""\n'
    '\n'
    'from conduit.feeds import parse_feed\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_negative_quantity_warns():\n'
    '    feed = (HEADER\n'
    '            + "A-1,BUY,TARNCORP,-5,10.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-2,SELL,ORNX,5,10.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '    assert "quantity" in warnings[0]["message"]\n'
    '\n'
    '\n'
    'def test_zero_price_warns():\n'
    '    feed = (HEADER\n'
    '            + "A-3,BUY,TARNCORP,5,0.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-4,SELL,ORNX,5,10.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '    assert "price" in warnings[0]["message"]\n'
    '\n'
    '\n'
    'def test_mixed_case_symbol_warns():\n'
    '    feed = (HEADER\n'
    '            + "A-5,BUY,TarnCorp,1,1.00,2025-01-02T09:00:01\\n"\n'
    '            + "A-6,SELL,ORNX,1,1.00,2025-01-02T09:00:02\\n")\n'
    '    rows, warnings = parse_feed(feed)\n'
    '    assert len(rows) == 1\n'
    '    assert len(warnings) == 1\n'
    '    assert warnings[0]["line"] == 2\n'
    '    assert "instrument" in warnings[0]["message"]\n',
]

CONTENT["tests/test_format.py"] = [
    # v1 (commit 10)
    '"""Tests for the canonical document renderer."""\n'
    '\n'
    'import json\n'
    '\n'
    'from conduit.format import render\n'
    '\n'
    'ORDER = {\n'
    '    "order_id": "O-1",\n'
    '    "fills": [\n'
    '        {"seq": 1, "side": "BUY", "instrument": "TARNCORP",\n'
    '         "quantity": 100, "price": 12.5, "timestamp": "2025-01-02T09:00:01"}],\n'
    '    "fill_count": 1,\n'
    '    "gross": 1250.0,\n'
    '}\n'
    '\n'
    '\n'
    'def test_render_single_fill():\n'
    '    out = render([ORDER], [])\n'
    '    doc = json.loads(out)\n'
    '    assert doc["orders"][0]["order_id"] == "O-1"\n'
    '    assert doc["orders"][0]["fill_count"] == 1\n'
    '    assert doc["orders"][0]["fills"][0]["seq"] == 1\n'
    '    assert doc["warnings"] == []\n'
    '\n'
    '\n'
    'def test_render_warnings():\n'
    '    out = render([], [{"line": 3, "message": "bad row"}])\n'
    '    doc = json.loads(out)\n'
    '    assert doc["orders"] == []\n'
    '    assert doc["warnings"] == [{"line": 3, "message": "bad row"}]\n'
    '\n'
    '\n'
    'def test_document_ends_with_newline():\n'
    '    assert render([ORDER], []).endswith(b"\\n")\n',
    # v2 (commit 19)
    '"""Tests for the canonical document renderer."""\n'
    '\n'
    'import json\n'
    '\n'
    'from conduit.format import render\n'
    '\n'
    'ORDER = {\n'
    '    "order_id": "O-1",\n'
    '    "fills": [\n'
    '        {"seq": 1, "side": "BUY", "instrument": "TARNCORP",\n'
    '         "quantity": 100, "price": 12.5, "timestamp": "2025-01-02T09:00:01"}],\n'
    '    "fill_count": 1,\n'
    '    "gross": 1250.0,\n'
    '    "fee": 1.88,\n'
    '    "net": 1248.12,\n'
    '    "sides": ["BUY"],\n'
    '}\n'
    '\n'
    '\n'
    'def test_render_single_fill():\n'
    '    out = render([ORDER], [])\n'
    '    doc = json.loads(out)\n'
    '    assert doc["orders"][0]["order_id"] == "O-1"\n'
    '    assert doc["orders"][0]["fill_count"] == 1\n'
    '    assert doc["orders"][0]["fills"][0]["seq"] == 1\n'
    '    assert doc["orders"][0]["fee"] == 1.88\n'
    '    assert doc["orders"][0]["sides"] == ["BUY"]\n'
    '    assert doc["warnings"] == []\n'
    '\n'
    '\n'
    'def test_render_warnings():\n'
    '    out = render([], [{"line": 3, "message": "bad row"}])\n'
    '    doc = json.loads(out)\n'
    '    assert doc["orders"] == []\n'
    '    assert doc["warnings"] == [{"line": 3, "message": "bad row"}]\n'
    '\n'
    '\n'
    'def test_document_ends_with_newline():\n'
    '    assert render([ORDER], []).endswith(b"\\n")\n',
]

CONTENT["tests/test_cli.py"] = [
    # v1 (commit 11)
    '"""End-to-end tests for the command-line entry point."""\n'
    '\n'
    'import json\n'
    'import subprocess\n'
    'import sys\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_round_trip(tmp_path):\n'
    '    feed = tmp_path / "feed.csv"\n'
    '    feed.write_text(HEADER\n'
    '                    + "A-1,BUY,TARNCORP,100,12.50,2025-01-02T09:00:01\\n")\n'
    '    out = tmp_path / "out.json"\n'
    '    r = subprocess.run([sys.executable, "-m", "conduit", str(feed),\n'
    '                        str(out)], capture_output=True, text=True)\n'
    '    assert r.returncode == 0, r.stderr\n'
    '    doc = json.loads(out.read_text())\n'
    '    assert doc["orders"][0]["order_id"] == "A-1"\n'
    '    assert doc["orders"][0]["fill_count"] == 1\n'
    '\n'
    '\n'
    'def test_missing_feed_returns_nonzero(tmp_path):\n'
    '    out = tmp_path / "out.json"\n'
    '    r = subprocess.run(\n'
    '        [sys.executable, "-m", "conduit", str(tmp_path / "nope.csv"),\n'
    '         str(out)], capture_output=True, text=True)\n'
    '    assert r.returncode != 0\n',
    # v2 (commit 28)
    '"""End-to-end tests for the command-line entry point."""\n'
    '\n'
    'import json\n'
    'import subprocess\n'
    'import sys\n'
    '\n'
    'HEADER = "order_id,side,instrument,quantity,price,timestamp\\n"\n'
    '\n'
    '\n'
    'def test_round_trip(tmp_path):\n'
    '    feed = tmp_path / "feed.csv"\n'
    '    feed.write_text(HEADER\n'
    '                    + "A-1,BUY,TARNCORP,100,12.50,2025-01-02T09:00:01\\n")\n'
    '    out = tmp_path / "out.json"\n'
    '    r = subprocess.run([sys.executable, "-m", "conduit", str(feed),\n'
    '                        str(out)], capture_output=True, text=True)\n'
    '    assert r.returncode == 0, r.stderr\n'
    '    doc = json.loads(out.read_text())\n'
    '    assert doc["orders"][0]["order_id"] == "A-1"\n'
    '    assert doc["orders"][0]["fill_count"] == 1\n'
    '\n'
    '\n'
    'def test_stdin_feed(tmp_path):\n'
    '    out = tmp_path / "out.json"\n'
    '    r = subprocess.run([sys.executable, "-m", "conduit", "-", str(out)],\n'
    '                       input=HEADER\n'
    '                       + "A-9,BUY,ORNX,3,4.50,2025-01-02T09:00:01\\n",\n'
    '                       capture_output=True, text=True)\n'
    '    assert r.returncode == 0, r.stderr\n'
    '    doc = json.loads(out.read_text())\n'
    '    assert doc["orders"][0]["order_id"] == "A-9"\n'
    '\n'
    '\n'
    'def test_missing_feed_returns_nonzero(tmp_path):\n'
    '    out = tmp_path / "out.json"\n'
    '    r = subprocess.run(\n'
    '        [sys.executable, "-m", "conduit", str(tmp_path / "nope.csv"),\n'
    '         str(out)], capture_output=True, text=True)\n'
    '    assert r.returncode != 0\n',
]

CONTENT["samples/feed_single.csv"] = [
    'order_id,side,instrument,quantity,price,timestamp\n'
    'ORD-1001,BUY,TARNCORP,100,12.50,2025-01-06T09:00:01\n'
    'ORD-1002,SELL,TARNCORP,75,13.10,2025-01-06T09:00:05\n'
    'ORD-1003,BUY,ORNX,400,8.20,2025-01-06T09:01:10\n'
    'ORD-1004,SELL,KESTREL-2,25,44.90,2025-01-06T09:02:00\n'
    'ORD-1005,BUY,ORNX,10,8.15,2025-01-06T09:03:30\n'
    'ORD-1006,SELL,TARNCORP,1500,12.90,2025-01-06T09:04:00\n',
]

CONTENT["samples/feed_mixed.csv"] = [
    'order_id,side,instrument,quantity,price,timestamp\n'
    'MIX-001,BUY,TARNCORP,250,12.60,2025-01-06T10:00:01\n'
    'MIX-002,SELL,ORNX,90,8.05,2025-01-06T10:00:10\n'
    'MIX-003,BUY,KESTREL-2,12,45.00,2025-01-06T10:01:00\n'
    'MIX-004,SELL,ORNX-A,3000,8.10,2025-01-06T10:02:00\n',
]

CONTENT["samples/feed_multi_line.csv"] = [
    'order_id,side,instrument,quantity,price,timestamp\n'
    'ORD-5001,BUY,TARNCORP,100,12.50,2025-01-10T09:00:01\n'
    'ORD-5001,BUY,TARNCORP,150,12.40,2025-01-10T09:00:02\n'
    'ORD-5002,SELL,ORNX,40,8.22,2025-01-10T09:01:00\n'
    'ORD-5002,SELL,ORNX,60,8.30,2025-01-10T09:01:05\n'
    'ORD-5002,SELL,ORNX,70,8.35,2025-01-10T09:01:09\n'
    'ORD-5003,BUY,KESTREL-2,5,44.10,2025-01-10T09:02:00\n',
]

# ---------------------------------------------------------------------------
# Commit plan: (message, {path: version_index}, [tags to create after commit])
# ---------------------------------------------------------------------------

PLAN = [
    ("chore: scaffold the conduit project layout",
     {"README.md": 0, ".gitignore": 0, "conduit/__init__.py": 0,
      "conduit/errors.py": 0}, []),
    ("feat(orders): add the OrderRow fill model",
     {"conduit/orders.py": 0}, []),
    ("feat(feeds): parse the vendor feed into rows",
     {"conduit/feeds.py": 0}, []),
    ("feat(aggregate): group rows into order envelopes with totals",
     {"conduit/aggregate.py": 0}, []),
    ("feat(format): render the canonical JSON document",
     {"conduit/format.py": 0}, []),
    ("feat(cli): add the python3 -m conduit round trip",
     {"conduit/cli.py": 0, "conduit/__main__.py": 0}, []),
    ("test(feeds): header and row-parsing coverage",
     {"tests/conftest.py": 0, "tests/test_feeds.py": 0}, []),
    ("test(orders): conversion and timestamp coverage",
     {"tests/test_orders.py": 0}, []),
    ("test(aggregate): envelope and total coverage",
     {"tests/test_aggregate.py": 0}, []),
    ("test(format): golden document rendering",
     {"tests/test_format.py": 0}, []),
    ("test(cli): end-to-end round trip",
     {"tests/test_cli.py": 0}, ["v0.1.0"]),
    ("docs: document the feed and canonical document",
     {"docs/format.md": 0, "README.md": 1}, []),
    ("feat(validate): semantic checks wired into parsing",
     {"conduit/validate.py": 0, "conduit/feeds.py": 1}, []),
    ("test(validate): warning path coverage",
     {"tests/test_validate.py": 0}, []),
    ("test(feeds): dialect tolerance",
     {"tests/test_feeds.py": 1}, []),
    ("feat(orders): fractional-second timestamps",
     {"conduit/orders.py": 1}, []),
    ("test(orders): fractional timestamp coverage",
     {"tests/test_orders.py": 1}, ["v0.2.0"]),
    ("feat(cli): report the fill count on stderr",
     {"conduit/cli.py": 1}, []),
    ("feat(format): render fee, net and sides",
     {"conduit/format.py": 1, "tests/test_format.py": 1,
      "docs/format.md": 1}, []),
    ("feat(aggregate): canonical fill ordering by timestamp then seq",
     {"conduit/aggregate.py": 1}, []),
    ("test(aggregate): ordering stability",
     {"tests/test_aggregate.py": 1, "docs/format.md": 2}, []),
    ("docs: add sample feeds and usage examples",
     {"samples/feed_single.csv": 0, "samples/feed_mixed.csv": 0,
      "samples/feed_multi_line.csv": 0, "README.md": 2}, ["v0.3.0"]),
    ("feat(validate): enforce the instrument symbol rule",
     {"conduit/validate.py": 1}, []),
    ("test(validate): symbol edge cases",
     {"tests/test_validate.py": 1}, []),
    ("perf(orders): precompile the timestamp pattern",
     {"conduit/orders.py": 2}, []),
    ("perf(aggregate): collapse duplicate order rows before the sort",
     {"conduit/aggregate.py": 2}, []),
    ("feat(cli): read the feed from stdin with '-'",
     {"conduit/cli.py": 2}, []),
    ("test(cli): stdin round trip",
     {"tests/test_cli.py": 1}, []),
    ("docs: troubleshooting section",
     {"README.md": 3}, []),
    ("chore: version 0.9.0",
     {"conduit/__init__.py": 1, "CHANGELOG.md": 0}, ["v0.9.0"]),
    ("fix(feeds): tolerate a leading BOM and blank lines",
     {"conduit/feeds.py": 2}, []),
    ("test(feeds): BOM and blank-line tolerance",
     {"tests/test_feeds.py": 2}, []),
    ("refactor(orders): split conversion helpers",
     {"conduit/orders.py": 3}, []),
    ("test(orders): refactored conversion coverage",
     {"tests/test_orders.py": 2}, []),
    ("chore: version 1.0.0",
     {"conduit/__init__.py": 2, "CHANGELOG.md": 1}, ["v1.0.0"]),
    ("docs: development notes",
     {"docs/contributing.md": 0}, []),
    ("chore: version 1.0.1",
     {"conduit/__init__.py": 3, "CHANGELOG.md": 2}, []),
    ("chore: ignore editor droppings",
     {".gitignore": 1}, []),
    ("docs: expected feed volumes",
     {"README.md": 4}, []),
    ("docs: known limits",
     {"README.md": 5}, []),
]

# The regression lands at PLAN index 25 (the "perf(aggregate): collapse"
# commit), between tags v0.3.0 and v0.9.0. Nothing else here names it.

def write_file(path, version, root):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="") as fh:
        fh.write(CONTENT[path][version])


def main():
    # Commit objects store the author/committer timezone offset; pin UTC so the
    # generated history has identical SHAs regardless of the builder's TZ.
    os.environ["TZ"] = "UTC"
    if os.path.isdir(REPO):
        import shutil
        shutil.rmtree(REPO)
    os.makedirs(REPO)
    git(["init", "-q", "-b", "main"])
    git(["config", "user.email", "build@localhost"])
    git(["config", "user.name", "build"])

    assert len(PLAN) == 40, "expect exactly 40 commits"
    for index, (msg, files, tags) in enumerate(PLAN, start=1):
        for path, version in files.items():
            write_file(path, version, REPO)
        commit(msg, index)
        for tag in tags:
            git(["tag", tag])

    # record the initial state for the verifier (outside /app so the agent
    # cannot see it at trial time without looking)
    head = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True)
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        fh.write("INITIAL_HEAD=%s\n" % head.stdout.strip())
        fh.write("SHIPPED_TAG=v1.0.0\n")

    # verify the fixture: suite is green at the shipped state
    n = subprocess.run(["python3", "-m", "pytest", "-q", "tests/"], cwd=REPO)
    if n.returncode != 0:
        print("FATAL: shipped test suite is not green", file=sys.stderr)
        sys.exit(1)

    commits = subprocess.run(["git", "-C", REPO, "rev-list", "--count", "HEAD"],
                             capture_output=True, text=True, check=True)
    print("conduit-tarn fixture built: %s commits, HEAD %s"
          % (commits.stdout.strip(), head.stdout.strip()[:12]))
    print("manifest written to %s" % MANIFEST)


if __name__ == "__main__":
    main()
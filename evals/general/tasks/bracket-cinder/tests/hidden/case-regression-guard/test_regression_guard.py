# Hidden case: guards that the fix must not break behaviours that already
# work — a single placeholder under a custom fmt still returns the raw
# (possibly non-text) value, default formatting still produces str, and a
# datetime spec under util.identity still produces identical text inside a
# multi-part template.
import datetime
import os
import sys
import unittest

_SRC = os.environ.get("GDL_SRC", "/app/src")
if _SRC not in sys.path:
    sys.path.insert(0, _SRC)

from gallery_dl import formatter, util  # noqa: E402


class TestRegressionGuards(unittest.TestCase):

    def test_single_placeholder_identity_returns_raw_value(self):
        fmt = formatter.parse("{t}", None, util.identity)
        self.assertIs(fmt.format_map({"t": 1262304000}), 1262304000)

    def test_single_placeholder_int_fmt_returns_int(self):
        fmt = formatter.parse("{t}", None, int)
        self.assertEqual(fmt.format_map({"t": 1262304000}), 1262304000)

    def test_default_fmt_multi_part_unchanged(self):
        fmt = formatter.parse("foo {t}", None)
        self.assertEqual(fmt.format_map({"t": 1262304000}), "foo 1262304000")

    def test_datetime_spec_multi_part_identity(self):
        fmt = formatter.parse(
            "stamp {ds:D%Y-%m-%dT%H:%M:%S%z} end", None, util.identity)
        self.assertEqual(
            fmt.format_map({"ds": "2010-01-01T01:00:00+01:00"}),
            "stamp 2010-01-01 00:00:00 end")

    def test_list_value_under_identity(self):
        fmt = formatter.parse("tags {l}", None, util.identity)
        self.assertEqual(fmt.format_map({"l": [1, 2, 3]}), "tags [1, 2, 3]")


if __name__ == "__main__":
    unittest.main()
# Hidden case: multi-part templates with custom formatting functions other
# than the ones the upstream regression test uses (int, dt.parse_iso,
# util.identity). Covers float, len, a bool-returning lambda, the !d
# timestamp conversion under identity, a missing key with an identity
# default, and a negative integer under int.
import os
import sys
import unittest

_SRC = os.environ.get("GDL_SRC", "/app/src")
if _SRC not in sys.path:
    sys.path.insert(0, _SRC)

from gallery_dl import formatter, util  # noqa: E402


class TestCustomFmtFunctions(unittest.TestCase):

    def test_float_fmt_embedded(self):
        fmt = formatter.parse("ratio {r}", None, float)
        self.assertEqual(fmt.format_map({"r": "12.5"}), "ratio 12.5")

    def test_len_fmt_returns_int(self):
        fmt = formatter.parse("len {s}", None, len)
        self.assertEqual(fmt.format_map({"s": "hello"}), "len 5")

    def test_bool_result_from_lambda(self):
        fmt = formatter.parse("flag {x}", None, lambda v: bool(int(v)))
        self.assertEqual(fmt.format_map({"x": "0"}), "flag False")

    def test_timestamp_conversion_with_identity(self):
        fmt = formatter.parse("x {t!d} y", None, util.identity)
        self.assertEqual(
            fmt.format_map({"t": 1262304000}),
            "x 2010-01-01 00:00:00 y")

    def test_missing_key_with_identity_default(self):
        fmt = formatter.parse("greet {missing}!", None, util.identity)
        self.assertEqual(fmt.format_map({}), "greet None!")

    def test_negative_int_with_int_fmt(self):
        fmt = formatter.parse("balance {amount} EUR", None, int)
        self.assertEqual(
            fmt.format_map({"amount": "-1234567890"}),
            "balance -1234567890 EUR")


if __name__ == "__main__":
    unittest.main()
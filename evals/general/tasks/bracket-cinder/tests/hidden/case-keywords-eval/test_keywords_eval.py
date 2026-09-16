# Hidden case: keyword-evaluation style templates — literal text mixed with
# {placeholders} whose resolved values are non-text (int, datetime, date,
# None). This is exactly the code path the product's keyword evaluation uses
# (formatter.parse(value, None, util.identity) for each configured keyword
# value); the upstream regression test only covers an int and an ISO datetime
# string under identity, so these inputs are not exercised there.
import datetime
import os
import sys
import unittest

_SRC = os.environ.get("GDL_SRC", "/app/src")
if _SRC not in sys.path:
    sys.path.insert(0, _SRC)

from gallery_dl import formatter, util  # noqa: E402


class TestKeywordEvalTemplates(unittest.TestCase):

    def test_url_template_with_int_placeholder(self):
        fmt = formatter.parse(
            "https://cdn.example.com/albums/{album_id}/{filename}",
            None, util.identity)
        out = fmt.format_map({"album_id": 1262304000, "filename": "img.jpg"})
        self.assertEqual(
            out, "https://cdn.example.com/albums/1262304000/img.jpg")

    def test_metadata_value_with_none_placeholder(self):
        fmt = formatter.parse("posted on {post_time}", None, util.identity)
        self.assertEqual(fmt.format_map({"post_time": None}), "posted on None")

    def test_value_with_datetime_placeholder(self):
        fmt = formatter.parse("cover-{published}.jpg", None, util.identity)
        self.assertEqual(
            fmt.format_map({"published": datetime.datetime(2010, 1, 1)}),
            "cover-2010-01-01 00:00:00.jpg")

    def test_text_before_and_after_placeholder(self):
        fmt = formatter.parse("<{id}>", None, util.identity)
        self.assertEqual(fmt.format_map({"id": 42}), "<42>")

    def test_multiple_placeholders_mixed_types(self):
        fmt = formatter.parse("{a}://{b}/{c}", None, util.identity)
        self.assertEqual(
            fmt.format_map({
                "a": "https",
                "b": "x",
                "c": datetime.date(2010, 1, 1),
            }),
            "https://x/2010-01-01")


if __name__ == "__main__":
    unittest.main()
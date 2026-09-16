#!/usr/bin/env python3
"""Complete FloatConverter.to_url fix for the werkzeug checkout at /app/src.

The defect: URL generation for <float:...> rules renders values with
str(float), which uses scientific notation for extreme magnitudes (e.g.
'1e-05'), and the router's own float regex (r"\\d+\\.\\d+") cannot match such
URLs, so generated links 404 and build->match round-trips fail.

The fix is a FloatConverter.to_url override that never emits scientific
notation. Values whose str() contains no 'e' are returned unchanged, so every
URL that already worked is byte-identical (the upstream suite's format
assertions are untouched). Values whose str() is scientific are expanded into
fixed notation with a trailing '.0' where the magnitude is integral, which
always matches the converter regex and round-trips to the same float, and the
sign is handled explicitly so signed converters (signed=True) are correct too.

This is deliberately COMPLETE: a naive fixed-point formatting fix (e.g.
f'{value:f}'.rstrip('0')) still breaks values whose fixed expansion ends in a
bare '.', such as 2.5e-07 ('0.'), 5.0 ('5.') and 1e20 ('...000.'), because the
regex requires a digit after the decimal point.
"""

import pathlib

CONVERTERS = pathlib.Path("/app/src/src/werkzeug/routing/converters.py")

METHOD = '''    def to_url(self, value: t.Any) -> str:
        # Never emit scientific notation: expand to fixed notation so the URL
        # always matches this converter's regex and round-trips to the same
        # value.
        value_str = str(float(value))
        if "e" not in value_str:
            return value_str
        sign = "-" if value_str.startswith("-") else ""
        if sign:
            value_str = value_str[1:]
        mantissa, _, exponent = value_str.partition("e")
        left, _, right = mantissa.partition(".")
        exp = int(exponent)
        if exp > 0:
            return f"{sign}{left}{right}{'0' * (exp - len(right))}.0"
        return f"{sign}0.{'0' * (-exp - len(left))}{left}{right}"

'''


def main() -> None:
    src = CONVERTERS.read_text(encoding="utf-8")
    anchor = "class UUIDConverter(BaseConverter):"
    assert anchor in src, "UUIDConverter anchor not found; source differs from pin"
    end = src.index(anchor)
    cls = src[src.index("class FloatConverter"):end]
    assert "def to_url" not in cls, "FloatConverter.to_url already present; fix already applied?"
    CONVERTERS.write_text(src[:end] + METHOD + src[end:], encoding="utf-8")
    print("patched FloatConverter.to_url")

    # sanity: the repaired library round-trips the required edge values
    import werkzeug.routing as r  # noqa: E402

    m = r.Map([r.Rule("/<float:v>", endpoint="a")])
    ad = m.bind("test.example")
    for v in (0.00001, 1e20, 2.5e-07, 5.0, 0.5, 1000.0):
        url = ad.build("a", {"v": v})
        assert "e" not in url and "E" not in url, (v, url)
        ep, params = ad.match(url)
        assert (ep, params["v"]) == ("a", v), (v, url, params)
    print("sanity round-trip OK")


if __name__ == "__main__":
    main()
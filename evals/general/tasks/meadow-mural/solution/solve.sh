#!/bin/bash
#
# Oracle for meadow-mural: author the deterministic SVG poster
# renderer and render the visible poster from the shipped spec.
# Creates /app/render_poster.py and /app/poster.svg.
#
set -eu

cat > /app/render_poster.py <<'PY'
#!/usr/bin/env python3
"""meadow-mural: deterministic parametric SVG poster renderer.

Usage:  python3 render_poster.py <spec.json> <out.svg>

The produced SVG is a pure function of the spec: identical input produces
byte-identical output (no timestamps, random ids, or environment-dependent
data). Pure Python stdlib only.

Exit codes:
  0  success
  1  usage or I/O error
  2  malformed spec (bad JSON, missing required keys, wrong types)

Layout contract (see the task instruction):
  * every numeric attribute goes through fmt() = format(round(x, 1), "g")
  * element order: svg root, bg rect, band rect, accent rule, title text,
    then per section (card rect, heading text, one <text> per body line),
    then the footer text
"""
import json
import sys
import xml.sax.saxutils as sax

REQUIRED_PALETTE = ["bg", "band", "card", "title", "heading", "body",
                    "footer", "accent"]
REQUIRED_LAYOUT = ["title_band_fraction", "margin_top", "margin_left",
                   "margin_right", "margin_bottom", "gap_vertical",
                   "title_font_size", "heading_font_size", "body_font_size",
                   "heading_line_height", "body_line_height",
                   "heading_body_gap", "card_padding_x", "accent_rule_height",
                   "footer_font_size", "footer_text"]


def r1(x):
    return round(x, 1)


def fmt(x):
    return format(r1(x), "g")


def body_lines(body):
    lines = body.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    return lines


def load_spec(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            spec = json.load(fh)
    except Exception:
        return None
    try:
        W = spec["canvas"]["width"]
        H = spec["canvas"]["height"]
        assert isinstance(W, int) and isinstance(H, int) and W > 0 and H > 0
        pal = spec["palette"]
        for key in REQUIRED_PALETTE:
            v = pal[key]
            assert isinstance(v, str) and len(v) == 7 and v[0] == "#"
        lay = spec["layout"]
        for key in REQUIRED_LAYOUT:
            assert key in lay
        assert isinstance(spec["title"], str)
        assert isinstance(spec["sections"], list)
        for sec in spec["sections"]:
            assert isinstance(sec, dict)
            assert isinstance(sec["heading"], str)
            assert isinstance(sec["body"], str)
    except Exception:
        return None
    return spec


def build_elements(spec):
    """Return [(localname, attrs, text-or-None), ...] in document order."""
    W = spec["canvas"]["width"]
    H = spec["canvas"]["height"]
    p = spec["palette"]
    L = spec["layout"]
    elems = []

    elems.append(("svg", {"xmlns": "http://www.w3.org/2000/svg",
                          "viewBox": "0 0 %s %s" % (W, H)}, None))

    # 1. background
    elems.append(("rect", {"x": "0", "y": "0", "width": fmt(W),
                           "height": fmt(H), "fill": p["bg"]}, None))

    # 2. title band
    hb = r1(L["title_band_fraction"] * H)
    elems.append(("rect", {"x": "0", "y": "0", "width": fmt(W),
                           "height": fmt(hb), "fill": p["band"]}, None))

    # 3. accent rule under the title band
    rw = r1(W - L["margin_left"] - L["margin_right"])
    arh = r1(L["accent_rule_height"])
    elems.append(("rect", {"x": fmt(L["margin_left"]), "y": fmt(hb),
                           "width": fmt(rw), "height": fmt(arh),
                           "fill": p["accent"]}, None))

    # 4. title text
    ty = r1(hb / 2 + 0.35 * L["title_font_size"])
    elems.append(("text", {"x": fmt(W / 2), "y": fmt(ty),
                           "text-anchor": "middle", "fill": p["title"],
                           "font-size": fmt(L["title_font_size"])},
                  spec["title"]))

    # 5..n. section bands
    by = r1(hb + arh + L["margin_top"])
    hh = L["heading_line_height"]
    hbg = L["heading_body_gap"]
    blh = L["body_line_height"]
    hfs = L["heading_font_size"]
    bfs = L["body_font_size"]
    cpx = L["card_padding_x"]
    for sec in spec["sections"]:
        lines = body_lines(sec["body"])
        lc = max(1, len(lines))
        sh = r1(hh + hbg + blh * lc)
        elems.append(("rect", {"x": fmt(L["margin_left"]), "y": fmt(by),
                               "width": fmt(rw), "height": fmt(sh),
                               "fill": p["card"]}, None))
        hy = r1(by + 0.5 * hh + 0.35 * hfs)
        elems.append(("text", {"x": fmt(L["margin_left"] + cpx), "y": fmt(hy),
                               "text-anchor": "start", "fill": p["heading"],
                               "font-size": fmt(hfs)}, sec["heading"]))
        for j in range(lc):
            bj = r1(by + hh + hbg + (j + 0.5) * blh + 0.35 * bfs)
            content = lines[j] if j < len(lines) else ""
            elems.append(("text", {"x": fmt(L["margin_left"] + cpx), "y": fmt(bj),
                                   "text-anchor": "start", "fill": p["body"],
                                   "font-size": fmt(bfs)}, content))
        by = r1(by + sh + L["gap_vertical"])

    # footer
    fy = r1(H - L["margin_bottom"])
    elems.append(("text", {"x": fmt(W / 2), "y": fmt(fy),
                           "text-anchor": "middle", "fill": p["footer"],
                           "font-size": fmt(L["footer_font_size"])},
                  L["footer_text"]))
    return elems


def render(spec):
    W = spec["canvas"]["width"]
    H = spec["canvas"]["height"]
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">' % (W, H)]
    for name, attrs, text in build_elements(spec):
        if name == "svg":
            continue
        attr_str = "".join(' %s="%s"' % (k, sax.escape(str(v), {'"': "&quot;"}))
                           for k, v in attrs.items())
        if text is None:
            out.append("  <%s%s/>" % (name, attr_str))
        else:
            out.append("  <%s%s>%s</%s>" % (name, attr_str,
                                            sax.escape(text), name))
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: python3 render_poster.py <spec.json> <out.svg>\n")
        return 1
    spec_path, out_path = argv[1], argv[2]
    spec = load_spec(spec_path)
    if spec is None:
        sys.stderr.write("render_poster: malformed or unreadable spec %s\n"
                         % spec_path)
        return 2
    svg = render(spec)
    try:
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(svg)
    except OSError as exc:
        sys.stderr.write("render_poster: cannot write %s: %s\n"
                         % (out_path, exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

python3 /app/render_poster.py /app/specs/poster_spec.json /app/poster.svg

echo "solve.sh done"
ls -l /app/render_poster.py /app/poster.svg

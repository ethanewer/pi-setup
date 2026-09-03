#!/usr/bin/env python3
"""meadow-mural verifier probe (dev copy).

Executes the agent's /app/render_poster.py on the visible spec and on every
hidden spec under /tests/hidden/specs/, parses each produced SVG with
xml.etree, and recomputes the full expected element tree from the spec with
its own independent implementation of the documented layout formulas. Also
validates /app/poster.svg against the visible spec and re-runs one case to
enforce byte-identical (deterministic) output.

Exit 0 on success; 1 on any failure.
"""
import glob
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
RENDERER = "/app/render_poster.py"
VISIBLE_SPEC = "/app/specs/poster_spec.json"
POSTER_SVG = "/app/poster.svg"
HIDDEN_PATTERN = "/tests/hidden/specs/*.json"
XML_DECL = b'<?xml version="1.0" encoding="utf-8"?>'

failures = []


def r1(x):
    return round(x, 1)


def fmt(x):
    return format(r1(x), "g")


def body_lines(body):
    lines = body.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    return lines


def expected_elements(spec):
    """Independent recompute: [(localname, attrs, text-or-None), ...]."""
    W = spec["canvas"]["width"]
    H = spec["canvas"]["height"]
    p = spec["palette"]
    L = spec["layout"]
    elems = []

    elems.append(("svg", {"xmlns": SVG_NS,
                          "viewBox": "0 0 %s %s" % (W, H)}, None))
    elems.append(("rect", {"x": "0", "y": "0", "width": fmt(W),
                           "height": fmt(H), "fill": p["bg"]}, None))
    hb = r1(L["title_band_fraction"] * H)
    elems.append(("rect", {"x": "0", "y": "0", "width": fmt(W),
                           "height": fmt(hb), "fill": p["band"]}, None))
    rw = r1(W - L["margin_left"] - L["margin_right"])
    arh = r1(L["accent_rule_height"])
    elems.append(("rect", {"x": fmt(L["margin_left"]), "y": fmt(hb),
                           "width": fmt(rw), "height": fmt(arh),
                           "fill": p["accent"]}, None))
    ty = r1(hb / 2 + 0.35 * L["title_font_size"])
    elems.append(("text", {"x": fmt(W / 2), "y": fmt(ty),
                           "text-anchor": "middle", "fill": p["title"],
                           "font-size": fmt(L["title_font_size"])},
                  spec["title"]))
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
    fy = r1(H - L["margin_bottom"])
    elems.append(("text", {"x": fmt(W / 2), "y": fmt(fy),
                           "text-anchor": "middle", "fill": p["footer"],
                           "font-size": fmt(L["footer_font_size"])},
                  L["footer_text"]))
    return elems


def localname(tag):
    return tag.rpartition("}")[2]


def check_svg_bytes(data, label):
    if not data.startswith(XML_DECL):
        failures.append("%s: file must start with the exact XML declaration"
                        % label)
    if b'xmlns="http://www.w3.org/2000/svg"' not in data:
        failures.append("%s: svg root must declare the default xmlns" % label)
    if b"<!--" in data:
        failures.append("%s: comments are not allowed in the SVG" % label)


def compare_tree(root, elems, label):
    if localname(root.tag) != "svg":
        failures.append("%s: root is not <svg>" % label)
        return
    # elems[0] is the svg root tuple; children must match elems[1:]
    want_root = elems[0]
    if dict(root.attrib) != {"viewBox": want_root[1]["viewBox"]}:
        failures.append("%s: root attributes %r != viewBox=%r"
                        % (label, dict(root.attrib), want_root[1]["viewBox"]))
    got = list(root)
    if len(got) != len(elems) - 1:
        failures.append("%s: expected %d child elements, got %d"
                        % (label, len(elems) - 1, len(got)))
        return
    for idx, (want, node) in enumerate(zip(elems[1:], got)):
        tag, attrs, text = want
        info = "%s element #%d" % (label, idx)
        if localname(node.tag) != tag:
            failures.append("%s: tag %r != %r" % (info, localname(node.tag), tag))
        if dict(node.attrib) != attrs:
            failures.append("%s: attributes %r != %r"
                            % (info, dict(node.attrib), attrs))
        if (node.text or "") != (text or ""):
            failures.append("%s: text %r != %r" % (info, node.text, text))


def run_renderer(spec_path, out_path, label):
    try:
        r = subprocess.run([sys.executable, RENDERER, spec_path, out_path],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        failures.append("%s: running %s raised %s" % (label, RENDERER, exc))
        return None
    if r.returncode != 0:
        failures.append("%s: renderer exit code %s (stderr: %s)"
                        % (label, r.returncode, (r.stderr or "").strip()[:300]))
        return None
    try:
        with open(out_path, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        failures.append("%s: cannot read output: %s" % (label, exc))
        return None
    check_svg_bytes(data, label)
    try:
        root = ET.fromstring(data)
    except Exception as exc:
        failures.append("%s: output is not well-formed XML: %s" % (label, exc))
        return None
    return root


def check_case(spec_path, out_path, label):
    try:
        with open(spec_path, encoding="utf-8") as fh:
            spec = json.load(fh)
    except Exception as exc:
        failures.append("%s: spec unreadable: %s" % (label, exc))
        return
    root = run_renderer(spec_path, out_path, label)
    if root is None:
        return
    compare_tree(root, expected_elements(spec), label)


def main():
    check_case(VISIBLE_SPEC, "/tmp/vellum_visible.svg", "visible")

    if not os.path.isfile(POSTER_SVG):
        failures.append("poster.svg deliverable missing")
    else:
        try:
            with open(POSTER_SVG, "rb") as fh:
                data = fh.read()
            check_svg_bytes(data, "poster.svg")
            root = ET.fromstring(data)
        except Exception as exc:
            failures.append("poster.svg unreadable/malformed: %s" % exc)
        else:
            with open(VISIBLE_SPEC, encoding="utf-8") as fh:
                vspec = json.load(fh)
                compare_tree(root, expected_elements(vspec), "poster.svg")

    try:
        r = subprocess.run([sys.executable, RENDERER, VISIBLE_SPEC,
                            "/tmp/vellum_visible2.svg"],
                           capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            failures.append("determinism rerun failed with exit %s" % r.returncode)
        else:
            with open("/tmp/vellum_visible.svg", "rb") as a, \
                 open("/tmp/vellum_visible2.svg", "rb") as b:
                if a.read() != b.read():
                    failures.append("renderer output is not deterministic")
    except Exception as exc:
        failures.append("determinism rerun raised %s" % exc)

    hidden = sorted(glob.glob(HIDDEN_PATTERN))
    if not hidden:
        failures.append("no hidden spec files found")
    for i, h in enumerate(hidden):
        check_case(h, "/tmp/vellum_hidden_%d.svg" % i,
                   "hidden[%s]" % os.path.basename(h))

    print("verify failures:", len(failures))
    for f in failures:
        print(" -", f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
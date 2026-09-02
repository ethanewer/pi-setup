#!/usr/bin/env python3
"""
Origin HTTP server for the vanta-mesa bench.

Serves the Fernbrook Nursery public offers page as HTML.

Usage:
    python3 origin.py <scenario-config.json> <port>

The scenario config declares the page title, the offer articles, the decoy
care-guide articles, and whitespace quirks.  The client program
(/app/solve.py) is written against the documented page contract and must
work for ANY scenario config.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;").replace("'", "&#39;"))


def price_text(p):
    if float(p) == int(p):
        return "$%d" % int(p)
    return "$%.2f" % float(p)


def article_html(o, joiner):
    parts = ['<article class="plant" data-sku="%s">' % esc(o["sku"]),
             '<h2 class="cultivar">%s</h2>' % esc(o["cultivar"]),
             '<span class="sku">%s</span>' % esc(o["sku"])]
    if o.get("price") is not None:
        parts.append('<span class="price">%s</span>' % price_text(o["price"]))
    st = o.get("stock")
    if st is None:
        pass
    elif st == "sold-out":
        parts.append('<span class="stock">Sold out</span>')
    else:
        parts.append('<span class="stock">In stock: %d</span>' % int(st))
    parts.append("</article>")
    return joiner.join(parts)


def render_page(cfg):
    messy = cfg.get("quirks", {}).get("messy_ws", False)
    gap = "\n      " if messy else ""
    decoys = gap.join(article_html(o, gap) for o in cfg.get("decoys", []))
    offers = gap.join(article_html(o, gap) for o in cfg.get("offers", []))
    n = len(cfg.get("offers", []))
    note = '<p class="note">%d cultivars offered this season</p>' % n
    sep = "\n\n" if messy else ""
    return (
        "<!DOCTYPE html>\n"
        "<html>\n"
        '<head><meta charset="utf-8"><title>%s</title></head>\n'
        "<body>\n"
        "<h1>%s</h1>\n"
        '<section id="care-guides">\n'
        "  <h2>Care guides</h2>\n"
        "%s%s%s\n"
        "</section>\n"
        '<section id="offers">\n'
        "  <h2>This season's offers</h2>\n"
        "%s%s%s\n"
        "%s\n"
        "</section>\n"
        "</body>\n"
        "</html>\n"
    ) % (esc(cfg["title"]), esc(cfg["title"]),
         gap, decoys, gap,
         gap, offers, gap,
         note)


class Handler(BaseHTTPRequestHandler):
    cfg = None

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path != "/":
            body = b"not found"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = render_page(self.cfg).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    cfg_path, port = sys.argv[1], int(sys.argv[2])
    with open(cfg_path, "r", encoding="utf-8") as fh:
        Handler.cfg = json.load(fh)
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()

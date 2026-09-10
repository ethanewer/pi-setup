# -*- coding: utf-8 -*-

# Copyright 2026 — authored for the general-agent-bench v4.2 wave.

"""Extractors for the fictional picdrome site.

Picdrome only ever exists as an offline loopback mock on 127.0.0.1, so every
URL carries a per-run local port that the extractor must not assume; it is
also completely agnostic to which gallery content it sees. Gallery pages are
UTF-8 HTML documents whose <title> identifies the gallery and whose media
links point at absolute paths under /media/.
"""

from urllib.parse import urlsplit

from .common import GalleryExtractor
from .. import text


class PicdromeGalleryExtractor(GalleryExtractor):
    """Extractor for single gallery pages on the picdrome site"""
    category = "picdrome"
    subcategory = "gallery"
    root = "http://127.0.0.1"
    pattern = r"(?:https?://)?127\.0\.0\.1(?::\d+)?/gallery/([^/?#]+)"
    example = "http://127.0.0.1/gallery/EXAMPLE/"
    filename_fmt = "{num:>03}.{extension}"

    def __init__(self, match):
        GalleryExtractor.__init__(self, match, url=match.string)
        origin = urlsplit(match.string)
        self.origin = f"{origin.scheme}://{origin.netloc}"
        self.slug = match[1]

    def metadata(self, page):
        title, _ = text.extract(page, "<title>", "</title>")
        return {
            "gallery_id": self.slug,
            "title"     : title,
        }

    def images(self, page):
        return [
            (self.origin + url, None)
            for url in text.extract_iter(page, '<a href="', '"')
            if url.startswith("/media/")
        ]
"""Client-side search index generation and querying.

The index is a JSON array written at build time; ``quaydoc search`` loads it
and ranks pages by term overlap using a tiny tf-style score.
"""

from __future__ import annotations

import json
import re

from quaydoc import markup

_TOKEN_RE = re.compile(r"[a-z0-9]+")
_STOP = {
    "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with",
    "at", "by", "is", "are", "was", "were", "be", "been", "this", "that",
    "these", "those", "it", "its", "as", "from", "your", "our", "their",
}
_SUFFIXES = ("ing", "ed", "es", "s", "ly", "tion", "ment")


def tokenize(text):
    """Lowercase word tokens of at least two characters, minus stop words."""
    return [t for t in _TOKEN_RE.findall(text.lower())
            if len(t) >= 2 and t not in _STOP]


def stem(word):
    """Aggressive-enough stemming for doc search."""
    for suffix in _SUFFIXES:
        if len(word) > len(suffix) + 2 and word.endswith(suffix):
            return word[: -len(suffix)]
    return word


def page_document(page):
    """The searchable text of one page."""
    parts = [page.title, page.description, markup.plaintext_blocks(page.blocks)]
    return " ".join(parts)


def page_terms(page):
    """Token counts for one page, with title terms weighted double."""
    counts = {}
    for term in tokenize(page.title):
        counts[term] = counts.get(term, 0) + 2
    for term in tokenize(markup.normalize(page.description)):
        counts[term] = counts.get(term, 0) + 1
    for term in tokenize(markup.plaintext_blocks(page.blocks)):
        counts[term] = counts.get(term, 0) + 1
    return counts


def build_index(pages):
    """Return the JSON-ready search index for ``pages``."""
    entries = []
    for page in pages:
        text = page_document(page)
        terms = tokenize(text)
        words = len(set(terms))
        term_counts = page_terms(page)
        entries.append({
            "title": page.title,
            "url": page.url,
            "text": markup.summary(page.blocks, 240),
            "terms": words,
            "keywords": _top_terms(terms),
            "weighted": {
                word: count for word, count in term_counts.items()
                if word in set(terms)
            },
        })
    return entries


def _top_terms(terms, limit=12):
    counts = {}
    for term in map(stem, terms):
        counts[term] = counts.get(term, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return [word for word, _ in ranked[:limit]]


def render_search_page(site):
    """Render the /search/ HTML page from the theme template."""
    from quaydoc import theme
    from quaydoc.template import Template
    template = Template(theme.TEMPLATES["search.html"], "search.html")
    return template.render({
        "site_title": site.config.title,
    })


def write_search_page(outdir, site):
    """Write ``search/index.html`` (or ``search.html`` flat build)."""
    from quaydoc.urls import output_rel
    from quaydoc.util import write_text
    from quaydoc import urls
    html = render_search_page(site)
    if site.config.pretty_urls:
        rel = "search/index.html"
    else:
        rel = "search.html"
    import os
    write_text(os.path.join(outdir, rel), html)


def write_index(outdir, entries):
    """Write ``search_index.json`` into ``outdir``."""
    from quaydoc.util import write_text
    payload = json.dumps(entries, indent=1, ensure_ascii=False)
    write_text(outdir + "/search_index.json", payload)
    return payload


def highlight_terms(text, terms, marker_before="<mark>",
                   marker_after="</mark>"):
    """Wrap occurrences of ``terms`` in ``text`` with markers."""
    import re as _re
    words = [w for w in _re.findall(r"[A-Za-z0-9]+", text)][:1]
    if not words:
        return text
    pattern = _re.compile("|".join(_re.escape(t) for t in terms
                                   if t), _re.I)
    return pattern.sub(lambda m: marker_before + m.group(0) + marker_after,
                       text)


def query(entries, terms):
    """Rank ``entries`` by overlap with ``terms`` (list of words)."""
    wanted = [stem(t) for t in tokenize(" ".join(terms))]
    if not wanted:
        return []
    scored = []
    for entry in entries:
        score = 0
        keywords = entry.get("keywords", [])
        weighted = entry.get("weighted", {})
        for term in wanted:
            if term in keywords:
                score += 3
            score += weighted.get(term, 0)
            text_terms = set(tokenize(entry.get("text", "")))
            for kw in keywords:
                if term in kw or kw in term:
                    score += 1
            if term in text_terms:
                score += 1
        if score:
            scored.append((score, entry))
    scored.sort(key=lambda pair: (-pair[0], pair[1]["title"].lower()))
    out = []
    for _, entry in scored:
        if "highlight" in entry:
            entry = dict(entry)
            entry["text"] = highlight_terms(
                entry.get("text", ""), wanted)
        out.append(entry)
    return out


def query_terms(query):
    """Split and stem a raw query string into search terms."""
    return [stem(term) for term in tokenize(query)]


def snippet(text, terms, radius=60, max_length=200):
    """Find the densest window of ``terms`` in ``text`` and return it.

    Falls back to the start of ``text`` when no term matches.  The window
    is widened to the nearest whitespace so returned snippets never split
    words.
    """
    lowered = text.lower()
    positions = []
    for term in set(terms):
        start = 0
        while True:
            found = lowered.find(term, start)
            if found < 0:
                break
            positions.append(found)
            start = found + len(term)
    if not positions:
        head = text[:max_length]
        cut = head[: head.rfind(" ")] if " " in head else head
        return (cut or head).rstrip() + ("…" if len(text) > len(head) else "")
    positions.sort()
    best = positions[0]
    best_span = -1
    for pos in positions:
        first = max(0, pos - radius)
        last = min(len(text), pos + radius)
        span = last - first
        if span > best_span:
            best_span = span
            best = pos
    start = max(0, best - radius)
    end = min(len(text), best + radius)
    if start > 0:
        while start < len(text) and not text[start].isspace():
            start += 1
        start = min(start + 1, len(text))
    if end < len(text):
        while end > start and not text[end].isspace():
            end -= 1
    lead = "…" if start > 0 else ""
    tail = "…" if end < len(text) else ""
    return lead + text[start:end].strip() + tail


def term_frequency(entries):
    """Documents-per-term map across ``entries`` (for IDF-style ranking)."""
    df = {}
    for entry in entries:
        for term in set(_top_terms(tokenize(entry.get("text", "")))):
            df[term] = df.get(term, 0) + 1
    return df


def preview(entries, query, limit=5):
    """Return up to ``limit`` (score, entry, snippet) tuples for ``query``."""
    scored = query(entries, query_terms(query))
    terms = [t for t in query_terms(query) if len(t) >= 2]
    out = []
    for entry in scored[:limit]:
        text = entry.get("text", entry.get("title", ""))
        out.append((entry, snippet(text, terms)))
    return out

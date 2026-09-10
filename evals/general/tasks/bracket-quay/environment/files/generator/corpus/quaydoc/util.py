"""Small shared helpers used across the package.

Kept deliberately dependency-free: everything here is a pure function or a
tiny filesystem utility so the rest of quaydoc can import it without pulling
in anything unexpected.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
import time
from datetime import datetime, timezone


def ensure_dir(path):
    """Create ``path`` (and parents) when missing; return the path."""
    os.makedirs(path, exist_ok=True)
    return path


def read_text(path):
    """Read a text file using quaydoc's normalised newline convention."""
    from quaydoc.textio import read_utf8_text
    return read_utf8_text(path)


def write_text(path, text):
    """Write ``text`` to ``path`` atomically (temp file + rename).

    Atomic replacement matters because quaydoc writes a whole site: a
    half-written page must never be observable by the checker or the dev
    server.
    """
    ensure_dir(os.path.dirname(os.path.abspath(path)))
    fd, tmp = tempfile.mkstemp(
        prefix=os.path.basename(path) + ".", dir=os.path.dirname(os.path.abspath(path)))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def sha256_hex(text):
    """Return the lowercase hex sha256 of ``text``."""
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()


def unique(seq):
    """Preserve-order unique items from ``seq`` (hashable items)."""
    seen = set()
    out = []
    for item in seq:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def flatten(nested):
    """Flatten one level of nesting out of a list of lists."""
    out = []
    for item in nested:
        out.extend(item)
    return out


_RE_WS = re.compile(r"\s+")


def collapse_ws(text):
    """Collapse runs of whitespace to a single space and strip."""
    return _RE_WS.sub(" ", text).strip()


def shorten(text, limit=110):
    """Truncate ``text`` to ``limit`` characters at a word boundary."""
    text = collapse_ws(text)
    if len(text) <= limit:
        return text
    cut = text[: limit - 1]
    head = cut[: cut.rfind(" ")] if " " in cut else cut
    return head.rstrip() + "…"


def human_bytes(n):
    """Format a byte count as a small human-readable string."""
    n = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{int(n)} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return f"{n:.1f} GB"


def now_iso():
    """Current UTC time as an ISO-8601 string (seconds precision)."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def deep_merge(base, override):
    """Merge ``override`` into ``base`` recursively (dicts only), returning a
    new dict.  Non-dict values in ``override`` win."""
    out = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def is_within(path, root):
    """True when ``path`` resolves inside ``root`` (lexically at least)."""
    path = os.path.abspath(path)
    root = os.path.abspath(root)
    common = os.path.commonpath([path, root])
    return common == root


def rel_display(path, root):
    """Human-friendly display of ``path`` relative to ``root``."""
    try:
        return os.path.relpath(path, root)
    except ValueError:
        return str(path)


_ESCAPE_TABLE = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
}


def escape_html(text):
    """Escape ``& < > ' "`` for HTML text content."""
    return _escape_table(text)


def escape_attr(text):
    """Escape text for use inside a double-quoted HTML attribute."""
    return _escape_table(text)


def _escape_table(text):
    return "".join(_ESCAPE_TABLE.get(ch, ch) for ch in str(text))



import os
import tarfile

from quaydoc.util import ensure_dir


def archive_dir(src_dir, dest_path):
    """Create ``dest_path`` (a ``.tar.gz``) from ``src_dir``'s contents.

    The archive contains the top-level entries of the build directory, not
    the directory itself, so ``tar -xzf`` reproduces the site root.
    """
    src_dir = os.path.abspath(src_dir)
    dest_path = os.path.abspath(dest_path)
    ensure_dir(os.path.dirname(dest_path))
    if not dest_path.endswith(".tar.gz"):
        dest_path += ".tar.gz"
    with tarfile.open(dest_path, "w:gz") as tar:
        for entry in sorted(os.listdir(src_dir)):
            tar.add(os.path.join(src_dir, entry), arcname=entry)
    return dest_path

def read_json(path, default=None):
    """Read a JSON file, returning ``default`` when absent or invalid."""
    import json
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_json(path, value, indent=1):
    """Atomic pretty JSON write."""
    import json
    write_text(path, json.dumps(value, indent=indent, ensure_ascii=False))


def file_age_seconds(path):
    """Age of ``path`` in seconds (or ``None`` when missing)."""
    try:
        return time.time() - os.path.getmtime(path)
    except OSError:
        return None


def as_boolean(value, default=False):
    """Parse a config value as a boolean, tolerant of common spellings."""
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    text = str(value).strip().lower()
    if text in {"1", "yes", "true", "on", "y", "t"}:
        return True
    if text in {"0", "no", "false", "off", "n", "f"}:
        return False
    return default


def coerce_int(value, default=None):
    """Parse ``value`` as an int, returning ``default`` on failure."""
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def format_duration(seconds):
    """Format ``seconds`` as ``1d 2h 3m 4s`` (omitting zero units)."""
    seconds = max(0, int(round(seconds)))
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes, seconds = divmod(seconds, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if seconds or not parts:
        parts.append(f"{seconds}s")
    return " ".join(parts)


def chunked(seq, size):
    """Yield ``seq`` in chunks of ``size`` (size must be positive)."""
    if size < 1:
        raise ValueError("chunk size must be at least 1")
    chunk = []
    for item in seq:
        chunk.append(item)
        if len(chunk) == size:
            yield chunk
            chunk = []
    if chunk:
        yield chunk


def checksum_file(path, chunk_size=65536):
    """Return the lowercase hex sha256 of a file's contents."""
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            block = fh.read(chunk_size)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()

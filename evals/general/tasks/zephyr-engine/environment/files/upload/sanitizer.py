"""Upload filter for the Zephyr web console.

`sanitize_upload_filename` maps an incoming upload's raw filename to the safe
name that should be persisted on the server. (Python port of the Java
UploadFilter used by the jar-upload endpoint.)
"""

import os

DANGEROUS_EXTS = [".jsp", ".war", ".js", ".jspx", ".sh", ".bat"]


def sanitize_upload_filename(raw):
    """Return the safe basename to store, or '' when unacceptable.

    NOTE(known-flaw): the port never rejected <traversal> or <mask> names.
    """
    if raw is None:
        return ""
    name = raw.strip()
    if name == "":
        return ""
    return os.path.basename(name)

"""gridlib: grid helpers the curlew build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-0.4.1"


def cell_bytes(cell):
    """UTF-8 bytes of a cell string (cheap sanity helper)."""
    return cell.encode("utf-8")

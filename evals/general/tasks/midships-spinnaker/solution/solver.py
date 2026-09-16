#!/usr/bin/env python3
"""Oracle solver for midships-spinnaker.

Writes the reproduction deliverable (/app/reproduce.py) and applies the
root-cause fix to the requests source tree at /app/src, then demonstrates the
reproduction passes against the repaired tree.
"""
import os
import pathlib
import sys
import textwrap

MODELS = pathlib.Path("/app/src/src/requests/models.py")

REPRODUCE = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    # Reproduction for the streaming-body bug in requests.
    #
    # An attribute-forwarding stream wrapper (a common "lazy file proxy"
    # pattern) is passed as the body of a POST request. On the unfixed build,
    # request preparation raises:
    #     TypeError: '<Proxy>' object is not iterable
    # On a fixed build, preparation succeeds, the wrapper is handled as a
    # streaming body and passed through untouched, this script prints
    # REPRO-OK and exits 0.
    import io
    import sys

    import requests


    class StreamProxy:
        \"\"\"Wrapper that forwards attribute lookups to a wrapped stream.\"\"\"

        def __init__(self, stream):
            self._stream = stream

        def __getattr__(self, name):
            return getattr(self._stream, name)


    def main() -> int:
        body = StreamProxy(io.BytesIO(b"streaming-body-payload"))
        req = requests.Request("POST", "http://example.invalid/post", data=body)
        prepared = req.prepare()  # raises TypeError here on the unfixed build
        assert prepared.body is body, "body must be passed through as a stream"
        assert prepared.body._stream.read() == b"streaming-body-payload"
        print(
            "REPRO-OK: attribute-forwarding stream wrapper handled as a streaming body"
        )
        return 0


    if __name__ == "__main__":
        sys.exit(main())
    """
)

# The single flawed classification block at the pinned parent commit.
OLD = """        if isinstance(data, Iterable) and not isinstance(
            data, (str, bytes, list, tuple, Mapping)
        ):"""

# The upstream fix: also recognise objects whose attribute lookups (e.g.
# __iter__) are forwarded to an underlying stream, instead of relying on the
# ABC isinstance check alone.
NEW = """        # data that proxies attributes to underlying objects needs hasattr
        is_iterable = isinstance(data, Iterable) or hasattr(data, "__iter__")
        if is_iterable and not isinstance(data, (str, bytes, list, tuple, Mapping)):"""


def apply_fix() -> None:
    source = MODELS.read_text()
    if OLD not in source:
        raise SystemExit(
            "could not locate the unfixed stream-classification block in "
            "src/requests/models.py (was the tree already repaired?)"
        )
    MODELS.write_text(source.replace(OLD, NEW, 1))


def main() -> int:
    pathlib.Path("/app/reproduce.py").write_text(REPRODUCE)
    os.chmod("/app/reproduce.py", 0o755)
    apply_fix()
    with open("/tmp/oracle_repro.out", "w") as fh:
        code = os.system(f"{sys.executable} /app/reproduce.py > /tmp/oracle_repro.out 2>&1")
    if code != 0:
        with open("/tmp/oracle_repro.out") as fh:
            sys.stderr.write(fh.read())
        raise SystemExit("reproduction failed on the repaired tree")
    with open("/tmp/oracle_repro.out") as fh:
        if not fh.read().startswith("REPRO-OK"):
            raise SystemExit("reproduction did not print REPRO-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
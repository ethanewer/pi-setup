"""Hidden case for bracket-ember: cross-process pickle handoff.

A multiprocessing pool pickles a worker's exception in the worker process and
unpickles it in the parent process, then re-raises it. This case performs
exactly that handoff with a separate interpreter -- the pickled bytes are
written by one process and loaded by another -- over several pickle
protocols. At the pinned parent commit the parent side crashes with
``TypeError: JSONDecodeError.__init__() missing 2 required positional
arguments: 'doc' and 'pos'``; after the fix every protocol round-trips with
msg/doc/pos and repr intact.
"""

import pickle
import subprocess
import sys

import pytest

from requests.exceptions import JSONDecodeError

MSG = "Extra data"
DOC = '{"responseCode":["706"]}{"responseCode":["706"]}'
POS = 36

_WORKER = (
    "import pickle, sys\n"
    "from requests.exceptions import JSONDecodeError\n"
    "argv = sys.argv[1:]\n"
    "msg, doc, pos_value, protocol = argv[0], argv[1], int(argv[2]), int(argv[3])\n"
    "error = JSONDecodeError(msg, doc, pos_value)\n"
    "sys.stdout.buffer.write(pickle.dumps(error, protocol=protocol))\n"
)


@pytest.mark.parametrize("protocol", [0, 2, 5, pickle.HIGHEST_PROTOCOL])
def test_exception_raised_in_one_process_unpickles_in_another(protocol):
    payload = subprocess.check_output(
        [sys.executable, "-c", _WORKER, MSG, DOC, str(POS), str(protocol)],
    )
    back = pickle.loads(payload)
    expect = JSONDecodeError(MSG, DOC, POS)
    assert repr(back) == repr(expect)
    assert back.msg == MSG
    assert back.doc == DOC
    assert back.pos == POS


def test_worker_side_serializes_without_error():
    # dumps must not even touch the broken reduce path in the producer.
    for protocol in (0, 1, 2, 3, 4, 5):
        error = JSONDecodeError(MSG, DOC, POS)
        payload = pickle.dumps(error, protocol=protocol)
        back = pickle.loads(payload)
        assert (back.msg, back.doc, back.pos) == (MSG, DOC, POS)
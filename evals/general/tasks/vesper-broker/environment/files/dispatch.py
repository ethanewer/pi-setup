"""Vesper message broker — queue consumer (stock, do not modify).

Reads a broker message from the path given on argv and deserializes it with
pickle.load. The deserialization is trusted; whatever the message reduces to
runs inside this process.
"""
import pickle
import sys


def handle(msg_path):
    with open(msg_path, "rb") as fh:
        obj = pickle.load(fh)
    print("dispatch: message consumed (%r)" % (type(obj).__name__,))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: dispatch.py <message.pkl>")
    handle(sys.argv[1])

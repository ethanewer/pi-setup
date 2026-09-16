"""Command line interface."""
import argparse
import sys

from . import __version__, engine


def build_parser():
    parser = argparse.ArgumentParser(
        prog="enrichd",
        description="Streaming event-enrichment service.  Reads JSON-lines "
                    "events from the input stream, writes one enriched "
                    "object per event to --output, and keeps going until "
                    "the stream closes.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("process", help="process an event stream")
    run.add_argument("--input", default="-",
                     help="input event stream; '-' reads stdin (default)")
    run.add_argument("--output", required=True,
                     help="path of the enriched .jsonl output")
    run.add_argument("--flush-every", type=int, default=8,
                     help="flush the output sink every N events")
    run.add_argument("--max-profiles", type=int, default=None,
                     help="cap the profile cache at N entries (default: unbounded)")

    ver = sub.add_parser("version", help="print the version and exit")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if args.command == "version":
        print(__version__)
        return 0
    if args.flush_every < 1:
        print("enrichd: --flush-every must be >= 1", file=sys.stderr)
        return 2
    return engine.run(args)

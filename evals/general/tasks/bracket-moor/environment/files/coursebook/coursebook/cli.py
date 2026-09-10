"""Command-line interface for coursebook.

Exit codes: 0 on success, 2 on any domain or usage error (a message is
printed to stderr). Successful mutations print nothing; the listing
commands print a header line followed by tab-separated rows.
"""

import argparse
import sys

from . import db
from . import store
from .errors import CoursebookError

EXIT_OK = 0
EXIT_ERR = 2


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="coursebook",
        description="Course registration ledger backed by SQLite",
    )
    sub = p.add_subparsers(dest="command", required=True)

    def add(name, help_text, args):
        sp = sub.add_parser(name, help=help_text)
        for arg, kw in args:
            sp.add_argument(arg, **kw)
        sp.set_defaults(handler=name)

    add("init", "create (or repair) an empty database", [("db", {})])
    add("add-student", "add a student", [
        ("db", {}), ("email", {}), ("name", {}),
    ])
    add("add-course", "add a course", [
        ("db", {}), ("code", {}), ("title", {}), ("seats", {"type": int}),
    ])
    add("register", "register a student for a course", [
        ("db", {}), ("email", {}), ("code", {}), ("semester", {}),
    ])
    add("complete", "mark an active registration completed", [
        ("db", {}), ("email", {}), ("code", {}), ("grade", {}),
    ])
    add("withdraw", "drop an active registration", [
        ("db", {}), ("email", {}), ("code", {}),
    ])
    add("roster", "list the roster for a course", [
        ("db", {}), ("code", {}),
    ])
    add("usage", "per-course seat usage", [("db", {})])
    add("history", "per-course history for a student", [
        ("db", {}), ("email", {}),
    ])
    return p


def _open(db_path):
    conn = db.connect(db_path)
    db.init_db(conn)
    return conn


def _print_rows(header, rows):
    print("\t".join(header))
    for row in rows:
        print("\t".join(str(v) for v in row))


def run_command(conn, command, args):
    if command == "init":
        db.init_db(conn)
    elif command == "add-student":
        store.add_student(conn, args.email, args.name)
    elif command == "add-course":
        store.add_course(conn, args.code, args.title, args.seats)
    elif command == "register":
        store.register(conn, args.email, args.code, args.semester)
    elif command == "complete":
        store.complete(conn, args.email, args.code, args.grade)
    elif command == "withdraw":
        store.withdraw(conn, args.email, args.code)
    elif command == "roster":
        _print_rows(("EMAIL", "NAME", "STATUS"), store.roster(conn, args.code))
    elif command == "usage":
        _print_rows(("CODE", "TITLE", "SEATS", "REGISTERED"),
                    store.seat_usage(conn))
    elif command == "history":
        _print_rows(("CODE", "TITLE", "SEMESTER", "STATUS", "GRADE"),
                    store.history(conn, args.email))
    else:
        raise CoursebookError(f"unknown command {command!r}")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        # argparse already printed the usage/help text
        return exc.code if isinstance(exc.code, int) else EXIT_ERR

    command = args.command
    if command == "init":
        conn = _open(args.db)
        conn.close()
        return EXIT_OK

    conn = _open(args.db)
    try:
        run_command(conn, command, args)
    except (CoursebookError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return EXIT_ERR
    finally:
        conn.close()
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
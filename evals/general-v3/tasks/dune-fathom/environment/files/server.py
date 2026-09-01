"""Fathom Edge Services -- API server (repo work-in-progress).

This is the starter version of the block-explorer backend that ships with the
repo. Several parts of it are wrong or unfinished on purpose; the task is to
repair it so it satisfies the contract in the task brief:

  * it must bind ALL interfaces on the fixed port 8787 (it currently binds
    only 127.0.0.1);
  * /render must emit its input as literal plain text, never as a Jinja
    template (it currently runs the user value through render_template_string,
    which is a server-side template injection hole);
  * the routes below are stubbed or skip required validation / error codes;
  * there is no error handler, so unknown routes return an HTML error page
    instead of a JSON error body.
"""
import sqlite3

from flask import Flask, Response, render_template_string, request

app = Flask(__name__)
PORT = 8787
DB = "/app/data/dump_chain.db"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/render")
def render_route():
    # TEMPLATE HOLE: the caller-supplied payload is rendered as a Jinja
    # template below, so an expression like {{7*7}} is executed (returns 49)
    # instead of being echoed literally. The task contract requires the value
    # to be treated as pure literal text.
    text = request.args.get("text", "")
    return render_template_string(text)


@app.get("/api/fibonacci")
def fib_route():
    raw = request.args.get("k")
    try:
        k = int(raw)
    except Exception:
        return Response('{"error": "invalid k"}', status=400, mimetype="application/json")
    if k < 0:
        return Response(
            '{"error": "k must be non-negative"}', status=400, mimetype="application/json"
        )

    def _fib(n):
        a, b = 0, 1
        for _ in range(n):
            a, b = b, a + b
        return a

    # Note: k > 200 is not rejected here and there is no JSON body on ~400.
    return {"k": k, "value": _fib(k)}


@app.get("/api/status/block/<string:bid>")
@app.get("/api/status/tx/<string:txid>")
def status_route(bid=None, txid=None):
    # STUB: always reports confirmed and never returns 400/404 with a JSON body.
    typ = "block" if bid is not None else "tx"
    ident = bid if bid is not None else txid
    return {"type": typ, "id": ident, "status": "confirmed"}


@app.get("/api/accounts")
def accounts_route():
    # STUB: no offset/limit validation, no paging, and the table may not exist.
    con = sqlite3.connect(DB)
    try:
        rows = con.execute(
            "SELECT id, address, balance FROM accounts ORDER BY id"
        ).fetchall()
    except sqlite3.OperationalError:
        rows = []
    finally:
        con.close()
    return {
        "total": len(rows),
        "result": [{"id": r[0], "address": r[1], "balance": r[2]} for r in rows],
    }


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=PORT)
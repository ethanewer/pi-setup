"""Minimal Bottle web service: session/login endpoint.

Security-relevant data flow (trace it!):

    user  (query param, attacker-controlled)
      -> build_session_cookie(user, role)
      -> response header  Set-Cookie   <-- HTTP security boundary
      ->  HTTP response emitted to the client

Right now `user` and `role` are interpolated verbatim into the Set-Cookie
response header with no newline sanitization. A CR / LF byte embedded in one
of them lets a client split the response and inject additional headers
(CWE-93 / HTTP response-splitting).
"""
from bottle import Bottle, request, response

app = Bottle()


def build_session_cookie(user, role):
    """Return the value for the Set-Cookie response header.

    `user` and `role` are attacker-controlled and must NEVER break out of the
    header line (no CR / LF, and no other header-delimiter characters).
    """
    return "session=%s; role=%s; HttpOnly" % (user, role)


@app.get('/login')
def login():
    user = request.query.get('user', 'guest') or 'guest'
    role = request.query.get('role', 'viewer') or 'viewer'
    response.headers['Set-Cookie'] = build_session_cookie(user, role)
    response.headers['Content-Type'] = 'text/plain; charset=utf-8'
    return 'login ok'


if __name__ == '__main__':
    from bottle import run
    run(app, host='127.0.0.1', port=8080, server='wsgiref')
from bottle import Bottle, request, response
from . import cookies, keys, transport

app = Bottle()


@app.get('/issue')
def issue():
    """Issue session id. token is attacker-controlled and flows:
    request.query -> keys.normalize -> transport.compose -> cookies.build
    -> Set-Cookie response header (security boundary).
    """
    token = request.query.get('token', keys.GUEST)
    token = keys.normalize(token)
    ttl = request.get_header('X-Session-TTL', '1800')
    payload = transport.compose(token, ttl)
    response.headers['Set-Cookie'] = cookies.build(payload, 'strict')
    response.headers['Content-Type'] = 'text/plain; charset=utf-8'
    return 'session ok'


if __name__ == '__main__':
    from bottle import run
    run(app, host='127.0.0.1', port=8080, server='wsgiref')
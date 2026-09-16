'use strict'
// cistern-cairn hidden case: an explicit far-future expires date and a
// negative maxAge are inputs the upstream tests do not use. In both cases the
// cleared cookie must still be expired immediately.
var express = require('/app/src'),
    request = require('/app/src/node_modules/supertest');

describe('cistern-cairn hidden: far-future expires and negative maxAge', function () {
  it('ignores a far-future caller-supplied expires date', function (done) {
    var app = express();
    app.use(function (req, res) {
      res.clearCookie('token', { path: '/', expires: new Date('Tue, 27 Sep 2100 00:00:00 GMT') }).end();
    });
    request(app)
      .get('/')
      .expect('Set-Cookie', 'token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT')
      .expect(200, done);
  });

  it('ignores a negative keep-alive maxAge', function (done) {
    var app = express();
    app.use(function (req, res) {
      res.clearCookie('sess', { path: '/', maxAge: -1 }).end();
    });
    request(app)
      .get('/')
      .expect(function (res) {
        var scs = res.headers['set-cookie'];
        var sc = Array.isArray(scs) ? scs[0] : scs;
        if (typeof sc !== 'string' || !sc) { throw new Error('no Set-Cookie header: ' + JSON.stringify(scs)); }
        if (/Max-Age/.test(sc)) { throw new Error('Max-Age must not be emitted: ' + sc); }
        var m = /Expires=([^;]+)/.exec(sc);
        if (!m) { throw new Error('no Expires attribute: ' + sc); }
        var t = Date.parse(m[1]);
        if (!(t < Date.now())) { throw new Error('expiration must be in the past: ' + sc); }
      })
      .expect(200, done);
  });
});

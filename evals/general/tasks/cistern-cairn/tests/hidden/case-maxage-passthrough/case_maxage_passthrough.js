'use strict'
// cistern-cairn hidden case: a large keep-alive maxAge must not keep a
// cleared cookie alive, while unrelated passthrough options (domain,
// httpOnly) are still honoured. The Set-Cookie must carry the forced 1970
// expiry and no Max-Age.
var express = require('/app/src'),
    request = require('/app/src/node_modules/supertest');

describe('cistern-cairn hidden: clearCookie with a keep-alive maxAge and passthrough options', function () {
  it('forces 1970 expiry, drops Max-Age, keeps domain and httpOnly', function (done) {
    var app = express();
    app.use(function (req, res) {
      res.clearCookie('sid', { path: '/admin', maxAge: 86400000, domain: 'example.com', httpOnly: true }).end();
    });
    request(app)
      .get('/')
      .expect('Set-Cookie', 'sid=; Domain=example.com; Path=/admin; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly')
      .expect(200, done);
  });
});

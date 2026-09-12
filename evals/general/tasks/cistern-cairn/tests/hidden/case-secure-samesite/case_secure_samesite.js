'use strict'
// cistern-cairn hidden case: clearing an API cookie with a keep-alive maxAge
// and secure/sameSite flags must still expire it immediately while keeping
// the flags.
var express = require('/app/src'),
    request = require('/app/src/node_modules/supertest');

describe('cistern-cairn hidden: clearCookie with secure + sameSite and a keep-alive maxAge', function () {
  it('clears immediately for an API scope regardless of maxAge', function (done) {
    var app = express();
    app.use(function (req, res) {
      res.clearCookie('tok', { path: '/api', maxAge: 900000, secure: true, sameSite: 'strict' }).end();
    });
    request(app)
      .get('/')
      .expect('Set-Cookie', 'tok=; Path=/api; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; SameSite=Strict')
      .expect(200, done);
  });
});

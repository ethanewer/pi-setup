'use strict'
// Reproduces the res.clearCookie bug at the pinned parent commit.
// Shows the Set-Cookie header produced when clearing with a keep-alive
// maxAge and when clearing with an explicit future expires date.
var express = require('/app/src');
var supertest = require('/app/src/node_modules/supertest');

var app = express();
app.use(function (req, res) {
  res.clearCookie('sid', { path: '/admin', maxAge: 1000 }).end();
});
supertest(app).get('/').end(function (err, res) {
  if (err) { console.log('FAIL:', err.message); process.exit(1); }
  console.log('maxAge:1000  ->', res.headers['set-cookie']);
});

var app2 = express();
app2.use(function (req, res) {
  res.clearCookie('tok', { path: '/admin', expires: new Date('Tue, 19 Jan 2038 03:14:07 GMT') }).end();
});
supertest(app2).get('/').end(function (err, res) {
  if (err) { console.log('FAIL:', err.message); process.exit(1); }
  console.log('expires:2038 ->', res.headers['set-cookie']);
});

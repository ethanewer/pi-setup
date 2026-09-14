#!/usr/bin/env node
// Build-time smoke reproduction for sill-ember (authored, not upstream):
// exercises res.location with a WHATWG URL instance and exits 0 only when
// the checkout produced a well-formed 200 with the Location header. On the
// buggy parent tree it must FAIL (HTTP 500, no Location header) — the
// Dockerfile asserts that during the build.
'use strict';
var supertest = require('/app/src/node_modules/supertest');
var express = require('/app/src');

var app = express();
app.use(function (req, res) {
  res.location(new URL('http://google.com/'));
  res.end();
});

supertest(app)
  .get('/')
  .end(function (err, res) {
    res = res || {};
    var ok = !err && res.status === 200 && res.headers['location'] === 'http://google.com/';
    console.log('smoke: ' + (ok
      ? 'UNEXPECTED-PASS'
      : 'REPRO-FAIL status=' + res.status + ' Location=' + JSON.stringify(res.headers && res.headers['location'])
        + (err ? (' err=' + err.message) : '')));
    process.exit(ok ? 0 : 1);
  });
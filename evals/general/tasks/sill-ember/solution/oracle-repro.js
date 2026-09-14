#!/usr/bin/env node
// Oracle reproduction script for sill-ember. Satisfies the /app/repro.js
// contract: `node /app/repro.js [REPO]`; loads the express checkout at REPO
// (default /app/src), exercises the affected res.location helper with a
// WHATWG URL instance through supertest in-process, exits 0 iff the
// checkout produces a well-formed response with the Location header, and
// exits non-zero otherwise (HTTP 500 / missing Location / any error).
'use strict';

var repo = process.argv[2] || '/app/src';
var express = require(repo);
var supertest = require('/app/src/node_modules/supertest');

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
    if (!ok) {
      console.error('repro: FAIL status=' + res.status + ' Location=' + JSON.stringify(res.headers && res.headers['location'])
        + (err ? (' err=' + err.message) : ''));
      process.exit(1);
    }
    console.log('repro: PASS Location: http://google.com/');
    process.exit(0);
  });
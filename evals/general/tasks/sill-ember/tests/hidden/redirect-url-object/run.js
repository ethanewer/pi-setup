// Hidden case for sill-ember: the redirect helper with a WHATWG URL
// object — the issue's own entry point (a user reports that res.redirect
// breaks on URL instances). The upstream regression test only calls
// res.location directly, so this exercises the same code path through a
// different, user-visible API: the redirect must be a 302 with the exact
// Location header; on the buggy tree the handler throws and supertest
// receives 500 with no Location header.
'use strict';
var express = require('/app/src');
var supertest = require('supertest');

var app = express();
app.get('/', function (req, res) {
  res.redirect(new URL('https://example.com/a?q=1'));
});

supertest(app)
  .get('/')
  .expect(302)
  .expect('Location', 'https://example.com/a?q=1')
  .end(function (err) {
    if (err) {
      console.error('FAIL redirect-url-object: ' + err.message);
      process.exit(1);
    }
    console.log('PASS redirect-url-object: 302 Location: https://example.com/a?q=1');
    process.exit(0);
  });
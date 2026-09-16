// Hidden case for sill-ember: res.location with a WHATWG URL object that
// carries a query string and a fragment — an input the upstream regression
// test (plain `new URL('http://google.com/')`) does not use. The full
// href, including query and fragment, must survive as the Location header.
'use strict';
var express = require('/app/src');
var supertest = require('supertest');

var app = express();
app.use(function (req, res) {
  res.location(new URL('https://example.com/a?q=1#frag'));
  res.end();
});

supertest(app)
  .get('/')
  .expect(200)
  .expect('Location', 'https://example.com/a?q=1#frag')
  .end(function (err) {
    if (err) {
      console.error('FAIL location-url-query-fragment: ' + err.message);
      process.exit(1);
    }
    console.log('PASS location-url-query-fragment: Location: https://example.com/a?q=1#frag');
    process.exit(0);
  });
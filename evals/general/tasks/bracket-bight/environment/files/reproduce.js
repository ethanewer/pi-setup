'use strict';

// bracket-bight reproducer: a response that carries an explicit
// Transfer-Encoding header and a body sent through res.send().
//
// The app owner sets Transfer-Encoding: chunked (the standard way to stream
// output) and then sends a body string. Every HTTP client is required to
// reject a response that carries both Content-Length and Transfer-Encoding,
// so today this script exits 1 with a parse error and the body never arrives.
//
// Run: node /app/reproduce.js   (expects the express checkout at /app/src)
//
// Correct behaviour after the bug is fixed:
//   Content-Length present: false | Transfer-Encoding present: true
//   body: "hello"
// and exit code 0.

var supertest = require('/app/src/node_modules/supertest');
var express = require('/app/src');

var app = express();
app.use(function (req, res) {
  res.status(200).set('Transfer-Encoding', 'chunked').send('hello');
});

supertest(app).get('/').end(function (err, res) {
  if (err) {
    console.log('FAIL:', err.message);
    console.log('The client rejected the response before the body arrived.');
    process.exit(1);
  }
  console.log('Content-Length present:', 'content-length' in res.headers,
              '| Transfer-Encoding present:', 'transfer-encoding' in res.headers);
  console.log('body:', JSON.stringify(res.text));
});
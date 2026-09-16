// Hidden case for sill-ember: another non-string but coercible location
// value. Upstream issue #5554 describes the contract as "non-string
// location values converted to their string form": an object whose
// toString() yields a relative path must be handled exactly like that path,
// not crash with 500.
'use strict';
var express = require('/app/src');
var supertest = require('supertest');

var app = express();
app.use(function (req, res) {
  var loc = { toString: function () { return '/from-object'; } };
  res.location(loc);
  res.end();
});

supertest(app)
  .get('/')
  .expect(200)
  .expect('Location', '/from-object')
  .end(function (err) {
    if (err) {
      console.error('FAIL location-other-coercible: ' + err.message);
      process.exit(1);
    }
    console.log('PASS location-other-coercible: Location: /from-object');
    process.exit(0);
  });
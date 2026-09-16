'use strict'

// bracket-bight hidden case 2: the control direction and the long-body code
// path. The fix must suppress Content-Length ONLY when a Transfer-Encoding
// header is present; normal responses keep their Content-Length, including
// long bodies that take the Buffer-conversion branch inside res.send().

var express = require('..');
var request = require('supertest');
var utils = require('./support/utils');

describe('bracket-bight hidden 2: Content-Length without Transfer-Encoding', function(){
  it('control: a plain short send keeps Content-Length and no Transfer-Encoding', function(done){
    var app = express();

    app.use(function(req, res){
      res.status(200).send('hello');
    });

    request(app)
      .get('/')
      .expect('Content-Length', '5')
      .expect(utils.shouldNotHaveHeader('Transfer-Encoding'))
      .expect(200, 'hello', done);
  })

  it('suppresses Content-Length for a long string body with Transfer-Encoding: chunked', function(done){
    var app = express();
    var longBody = Array(2000).join('z'); // length 1999: takes the Buffer-branch in res.send()

    app.use(function(req, res){
      res.status(200).set('Transfer-Encoding', 'chunked').send(longBody);
    });

    request(app)
      .get('/')
      .expect(utils.shouldNotHaveHeader('Content-Length'))
      .expect(utils.shouldHaveHeader('Transfer-Encoding'))
      .expect(200, longBody, done);
  })

  it('control: a long string body without Transfer-Encoding keeps Content-Length', function(done){
    var app = express();
    var longBody = Array(2000).join('x');

    app.use(function(req, res){
      res.send(longBody);
    });

    request(app)
      .get('/')
      .expect('Content-Length', String(Buffer.byteLength(longBody)))
      .expect(200, longBody, done);
  })
})
'use strict'

// bracket-bight hidden case 1: Transfer-Encoding combined with body kinds the
// upstream regression test does not use (JSON objects and Buffers instead of
// an empty string). The guard that suppresses Content-Length lives in
// res.send(), so every body type that flows through it must still avoid the
// forbidden Content-Length + Transfer-Encoding pair while the payload arrives
// intact.

var assert = require('node:assert')
var express = require('..');
var request = require('supertest');
var utils = require('./support/utils');

describe('bracket-bight hidden 1: Transfer-Encoding with JSON and Buffer bodies', function(){
  ['chunked', 'gzip', 'deflate', 'compress'].forEach(function(encoding){
    it('sends a JSON body without Content-Length when Transfer-Encoding is ' + encoding, function(done){
      var app = express();

      app.use(function(req, res){
        res.status(200).set('Transfer-Encoding', encoding).send({ ok: true, n: 42 });
      });

      request(app)
        .get('/')
        .expect(utils.shouldNotHaveHeader('Content-Length'))
        .expect(utils.shouldHaveHeader('Transfer-Encoding'))
        .expect('Content-Type', 'application/json; charset=utf-8')
        .expect(200, '{"ok":true,"n":42}', done);
    })
  })

  it('sends a Buffer body without Content-Length when Transfer-Encoding is chunked', function(done){
    var app = express();

    app.use(function(req, res){
      res.status(200).set('Transfer-Encoding', 'chunked').send(Buffer.from([0xde, 0xad, 0xbe, 0xef]));
    });

    request(app)
      .get('/')
      .expect(utils.shouldNotHaveHeader('Content-Length'))
      .expect(utils.shouldHaveHeader('Transfer-Encoding'))
      .expect(function(res){
        assert.strictEqual(Buffer.from(res.body).toString('hex'), 'deadbeef')
      })
      .expect(200, done);
  })
})
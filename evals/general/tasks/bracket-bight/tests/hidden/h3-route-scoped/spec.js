'use strict'

// bracket-bight hidden case 3: Transfer-Encoding scoped to one route of a
// multi-route application. The guard must be per-response: the streamed route
// loses Content-Length, the sibling route keeps it, across sequential
// requests made through the same supertest agent.

var express = require('..');
var request = require('supertest');
var utils = require('./support/utils');

describe('bracket-bight hidden 3: Transfer-Encoding scoped to one route', function(){
  it('only the streamed route drops Content-Length; the plain route keeps it', function(done){
    var app = express();

    app.use('/stream', function(req, res){
      res.status(200).set('Transfer-Encoding', 'chunked').send('streamed');
    });
    app.use('/plain', function(req, res){
      res.status(200).send('plain');
    });

    request(app)
      .get('/stream')
      .expect(utils.shouldNotHaveHeader('Content-Length'))
      .expect(utils.shouldHaveHeader('Transfer-Encoding'))
      .expect(200, 'streamed')
      .then(function(){
        request(app)
          .get('/plain')
          .expect('Content-Length', '5')
          .expect(utils.shouldNotHaveHeader('Transfer-Encoding'))
          .expect(200, 'plain')
          .end(done);
      })
      .catch(function(err){
        done(err || new Error('unexpected failure'));
      });
  })
})
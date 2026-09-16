#!/usr/bin/env node
'use strict'

// gaff-gate hidden-case runner.
//
// Drives the framework under test IN /app/src (never a copy) through its own
// public API and its own HTTP stack and asserts the status-code contract:
//   * res.status(code) / res.sendStatus(code) must throw for every class of
//     invalid code (TypeError for non-integers, RangeError for integers
//     outside 100..999, message beginning with 'Invalid status code:');
//   * valid integers, including the boundaries 100 and 999, must be accepted
//     and set; at the HTTP level an invalid code must surface as a 500 whose
//     body contains 'Invalid status code';
//   * the hidden inputs below are author-added classes that the upstream
//     regression test does not use.
//
// Exit 0 iff every check passes. Reads its input tables from /tests/hidden.

var fs = require('fs')
var path = require('path')

var SRC = '/app/src'
var express = require(path.join(SRC))
var request = require(path.join(SRC, 'node_modules', 'supertest'))
var lib = require(path.join(SRC, 'lib', 'response'))

var HIDDEN_DIR = '/tests/hidden'

var failures = []
function check(cond, msg) {
  if (!cond) failures.push(msg)
}

// For res.sendStatus the API-level check only makes sense for inputs that
// are rejected: the throw happens in the validating entry point before any
// response machinery is touched, whereas a bare prototype object has no
// request context for the send() path.
function apiThrows(method, input, expectType, label) {
  var res = Object.create(lib)
  try {
    res[method](input)
    failures.push(method + '(' + label + ') did not throw')
  } catch (e) {
    if (!(e instanceof Error)) {
      failures.push(method + '(' + label + ') threw a non-Error: ' + String(e))
    } else {
      if (expectType && e.constructor.name !== expectType) {
        failures.push(method + '(' + label + ') threw ' + e.constructor.name + ', expected ' + expectType + ' (' + e.message + ')')
      }
      if (e.message.indexOf('Invalid status code:') !== 0) {
        failures.push(method + '(' + label + ') threw "' + e.message + '" but the message must begin with "Invalid status code:"')
      }
    }
  }
}

function apiValid(method, input, label) {
  var res = Object.create(lib)
  try {
    var ret = res[method](input)
    check(ret === res, method + '(' + label + ') must return the response for chaining')
    check(res.statusCode === input, method + '(' + label + ') must set statusCode, got ' + res.statusCode)
  } catch (e) {
    failures.push(method + '(' + label + ') unexpectedly threw: ' + (e && e.message))
  }
}

// ---------------------------------------------------------------------------
// HTTP-level checks: real request through the project's own express app
// ---------------------------------------------------------------------------
function httpInvalid(method, input, label) {
  return new Promise(function (resolve) {
    var app = express()
    app.use(function (req, res) {
      if (method === 'sendStatus') res.sendStatus(input)
      else res.status(input).end()
    })
    request(app).get('/').expect(500).expect(/Invalid status code/).end(function (err) {
      if (err) failures.push('HTTP ' + method + '(' + label + '): expected 500 with body containing "Invalid status code", got failure: ' + err.message)
      resolve()
    })
  })
}

function httpValid(method, input, label) {
  return new Promise(function (resolve) {
    var app = express()
    app.use(function (req, res) {
      if (method === 'sendStatus') res.sendStatus(input)
      else res.status(input).end()
    })
    request(app).get('/').expect(input).end(function (err) {
      if (err) failures.push('HTTP ' + method + '(' + label + '): expected status ' + input + ', got: ' + err.message)
      resolve()
    })
  })
}

// ---------------------------------------------------------------------------
var checks = []

var cases = fs.readdirSync(HIDDEN_DIR).filter(function (d) {
  return fs.statSync(path.join(HIDDEN_DIR, d)).isDirectory()
}).sort()
if (!cases.length) { failures.push('no hidden case directories found under ' + HIDDEN_DIR) }

var total = 0

cases.forEach(function (dir) {
  var cfg = JSON.parse(fs.readFileSync(path.join(HIDDEN_DIR, dir, 'case.json'), 'utf8'))
  var method = cfg.method
  console.log('  case ' + dir + ' (method res.' + method + ')')

  ;(cfg.invalid || []).forEach(function (c) {
    var label = typeof c.in === 'string' ? JSON.stringify(c.in) : String(c.in)
    total++
    apiThrows(method, c.in, c.type, label)
    checks.push(httpInvalid(method, c.in, label))
  })
  // valid entries: api + http
  ;(cfg.valid || []).forEach(function (c) {
    var label = typeof c === 'string' ? JSON.stringify(c) : String(c)
    total++
    apiValid(method, c, label)
    checks.push(httpValid(method, c, label))
  })
  // http-only valid entries (e.g. res.sendStatus needs the full response
  // machinery and cannot be called on a bare prototype object)
  ;(cfg.http_valid || []).forEach(function (c) {
    var label = typeof c === 'string' ? JSON.stringify(c) : String(c)
    total++
    checks.push(httpValid(method, c, label))
  })
  // api-only valid entries (e.g. status 100: valid per the contract, but
  // Node treats a 100 writeHead as Expect: 100-continue at the HTTP level)
  ;(cfg.api_valid || []).forEach(function (c) {
    var label = typeof c === 'string' ? JSON.stringify(c) : String(c)
    total++
    apiValid(method, c, label)
  })
})

Promise.all(checks).then(function () {
  if (failures.length) {
    console.log('verify.js: ' + failures.length + ' of ' + total + ' hidden checks failed:')
    failures.forEach(function (f) { console.log('  - ' + f) })
    process.exit(1)
  }
  console.log('verify.js: all ' + total + ' hidden checks passed')
  process.exit(0)
})
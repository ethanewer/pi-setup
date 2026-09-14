#!/usr/bin/env node
'use strict'

// gaff-gate oracle reproduction: a discriminating regression for the
// silently-accepted-invalid-status-code defect.
//
// Loads the framework under test from /app/src (never a copy), drives the
// response prototype through its public status-setting API, and exits 0 only
// if every invalid status code in the class is rejected with an Error whose
// message begins with "Invalid status code:" while every valid integer status
// (including boundary 999) is accepted.
//
// Exit status: 0 = all assertions hold (tree repaired), 1 = the defect is
// present (some invalid code was silently accepted), 2 = cannot load the tree.
// Never reads anything under /tests.

var path = require('path')
var fs = require('fs')

var SRC = '/app/src'
if (!fs.existsSync(path.join(SRC, 'lib', 'response.js'))) {
  console.error('reproduce.js: cannot find the framework under test at ' + SRC)
  process.exit(2)
}

// The framework's response prototype: `status` is a prototype method, so a
// fresh object created from the exports gets it via the prototype chain.
var lib = require(path.join(SRC, 'lib', 'response'))
if (typeof lib.status !== 'function') {
  console.error('reproduce.js: lib response exports have no status method; is this the right tree?')
  process.exit(2)
}

var INVALID = [
  // [value, display, kind]
  [99, '99', 'integer below 100'],
  [0, '0', 'integer below 100'],
  [-1, '-1', 'negative integer'],
  [1000, '1000', 'integer above 999'],
  [200.5, '200.5', 'non-integer'],
  [302.25, '302.25', 'non-integer'],
  ['200', '"200"', 'numeric string'],
  ['abc', '"abc"', 'non-numeric string'],
  [NaN, 'NaN', 'NaN'],
  [undefined, 'undefined', 'missing value'],
  [true, 'true', 'boolean']
]

var VALID = [200, 999]

var failures = []
var checked = 0

INVALID.forEach(function (entry) {
  var code = entry[0]
  var res = Object.create(lib)
  checked++
  try {
    res.status(code)
    failures.push('res.status(' + entry[1] + ') (' + entry[2] + ') was silently accepted')
  } catch (e) {
    if (!(e instanceof Error)) {
      failures.push('res.status(' + entry[1] + ') threw a non-Error: ' + String(e))
    } else if (e.message.indexOf('Invalid status code:') !== 0) {
      failures.push('res.status(' + entry[1] + ') threw "' + e.message + '" but the message must begin with "Invalid status code:"')
    }
  }
})

VALID.forEach(function (code) {
  var res = Object.create(lib)
  checked++
  try {
    var returned = res.status(code)
    if (returned !== res) {
      failures.push('res.status(' + code + ') did not return the response for chaining')
    } else if (res.statusCode !== code) {
      failures.push('res.status(' + code + ') did not set statusCode (' + res.statusCode + ')')
    }
  } catch (e) {
    failures.push('res.status(' + code + ') unexpectedly threw: ' + (e && e.message))
  }
})

if (failures.length) {
  console.log('reproduce.js: defect present — ' + failures.length + ' of ' + checked + ' checks failed:')
  failures.forEach(function (f) { console.log('  - ' + f) })
  process.exit(1)
}

console.log('reproduce.js: all ' + checked + ' checks passed: invalid status codes rejected, valid codes accepted')
process.exit(0)
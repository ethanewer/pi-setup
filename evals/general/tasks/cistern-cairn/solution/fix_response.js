'use strict'
// Oracle for cistern-cairn: applies the res.clearCookie fix to lib/response.js
// in the checked-out express tree.
//
// The parent body lets caller-supplied options win over the forced past
// expiry, so a maxAge or an explicit expires date postpones the deletion. The
// fix forces the past expiry last (so it can never be overridden) and drops
// maxAge, while still passing every unrelated caller option through to
// res.cookie.
var fs = require('fs');

var path = process.argv[2];
var src = fs.readFileSync(path, 'utf8');

var BUGGY = [
  'res.clearCookie = function clearCookie(name, options) {',
  "  var opts = merge({ expires: new Date(1), path: '/' }, options);",
  '',
  "  return this.cookie(name, '', opts);",
  '};'
].join('\n');

var FIXED = [
  'res.clearCookie = function clearCookie(name, options) {',
  '  // Force cookie expiration by setting expires to the past',
  "  const opts = { path: '/', ...options, expires: new Date(1)};",
  '  // ensure maxAge is not passed',
  '  delete opts.maxAge',
  '',
  "  return this.cookie(name, '', opts);",
  '};'
].join('\n');

if (src.indexOf(BUGGY) === -1) {
  console.error('cistern-cairn oracle: expected parent clearCookie body not found; aborting');
  process.exit(1);
}

src = src.replace(BUGGY, FIXED);
fs.writeFileSync(path, src);
console.log('oracle: patched lib/response.js');

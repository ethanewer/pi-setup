#!/usr/bin/env node
'use strict';
/*
 * Treadmill-core per-turn cell decision function (pure JavaScript).
 *
 * The cell is a puzzle state object describing an ordered line of tiles:
 *   cell = {
 *     line:   [ { tile: <number>, open: <bool> }, ... ],
 *     cursor: <number>            // index of the currently active tile
 *   }
 *
 * decide(cell) returns the action string the cursor may legally take:
 *   - "left"  : move to the adjacent left  tile, if it exists and open !== false
 *   - "right" : move to the adjacent right tile, if it exists and open !== false
 *   - "stay"  : when neither move is allowed (or the state is malformed)
 *
 * Ties are resolved in favour of the neighbour carrying the larger tile value;
 * a perfect tie prefers "right" over "left".
 *
 * No external imports, no classes, no network: pure functions only.
 *
 * CLI:  node game.js <input.json>   -> prints the decided action to stdout
 *       node game.js --self         -> emits "0" to confirm the module loads
 */

function decide(cell) {
  if (!cell || !Array.isArray(cell.line)) {
    return 'stay';
  }
  var line = cell.line;
  var cur = cell.cursor;
  if (typeof cur !== 'number' || !isFinite(cur) || cur < 0 || cur >= line.length) {
    return 'stay';
  }
  var options = [];
  var left = line[cur - 1];
  var right = line[cur + 1];
  if (left && left.open !== false) {
    options.push({ d: 'left', v: typeof left.tile === 'number' ? left.tile : 0 });
  }
  if (right && right.open !== false) {
    options.push({ d: 'right', v: typeof right.tile === 'number' ? right.tile : 0 });
  }
  if (options.length === 0) {
    return 'stay';
  }
  options.sort(function (a, b) {
    if (b.v !== a.v) { return b.v - a.v; }     // higher tile wins
    if (a.d === b.d) { return 0; }
    return a.d === 'right' ? -1 : 1;            // tie -> prefer right
  });
  return options[0].d;
}

module.exports = { decide: decide };

if (require.main === module) {
  var args = process.argv.slice(2);
  if (args[0] === '--selfcheck') {
    console.log('0');
  } else {
    var data = JSON.parse(require('fs').readFileSync(args[0], 'utf8'));
    console.log(decide(data));
  }
}
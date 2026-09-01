'use strict';
/*
 * Ashen-lattice lantern-crawl per-turn decision function (pure JavaScript).
 *
 * state = {
 *   grid:    [[<number>, ...], ...],   // jagged-allowed rows of numeric signals
 *   row:     <int>,                    // drone's current row
 *   col:     <int>,                    // drone's current column
 *   visited: [[r, c], ...]             // (optional) cells already claimed
 * }
 *
 * choose(state) returns exactly one allowed action string:
 *   "north" | "east" | "south" | "west" | "hold"
 *
 * A neighbour is allowed iff it is inside the grid (per-row length), its
 * value is a finite number, and it is not marked visited. Among allowed
 * neighbours pick the LARGEST value; ties keep the first of the priority
 * order north > east > south > west. No allowed neighbour or any malformed
 * state -> "hold".
 *
 * No external imports, no classes, no network: pure functions only.
 */
function choose(state) {
  if (!state || typeof state !== 'object') {
    return 'hold';
  }
  var grid = state.grid;
  if (!Array.isArray(grid) || grid.length === 0) {
    return 'hold';
  }
  var r = state.row;
  var c = state.col;
  var intish = function (v) {
    return typeof v === 'number' && isFinite(v) && Math.floor(v) === v;
  };
  if (!intish(r) || !intish(c)) {
    return 'hold';
  }
  if (r < 0 || r >= grid.length) {
    return 'hold';
  }
  var rowArr = grid[r];
  if (!Array.isArray(rowArr) || c < 0 || c >= rowArr.length) {
    return 'hold';
  }
  var seen = {};
  if (Array.isArray(state.visited)) {
    for (var i = 0; i < state.visited.length; i++) {
      var p = state.visited[i];
      if (Array.isArray(p) && p.length >= 2 && intish(p[0]) && intish(p[1])) {
        seen[p[0] + ',' + p[1]] = true;
      }
    }
  }
  var dirs = [
    { a: 'north', dr: -1, dc: 0 },
    { a: 'east',  dr: 0,  dc: 1 },
    { a: 'south', dr: 1,  dc: 0 },
    { a: 'west',  dr: 0,  dc: -1 }
  ];
  var best = null;
  for (var j = 0; j < dirs.length; j++) {
    var d = dirs[j];
    var nr = r + d.dr;
    var nc = c + d.dc;
    if (nr < 0 || nr >= grid.length) {
      continue;
    }
    var nrow = grid[nr];
    if (!Array.isArray(nrow) || nc < 0 || nc >= nrow.length) {
      continue;
    }
    var v = nrow[nc];
    if (typeof v !== 'number' || !isFinite(v)) {
      continue;
    }
    if (seen[nr + ',' + nc]) {
      continue;
    }
    if (best === null || v > best.v) {  // strict > keeps earlier dir on tie
      best = { a: d.a, v: v };
    }
  }
  return best === null ? 'hold' : best.a;
}

module.exports = { choose: choose };

#!/usr/bin/env node
'use strict';
/*
 * ashen-lattice batch simulator driver.
 *
 *   node /app/simulate.js <states.json> <out.json>
 *
 * Reads a JSON list of lantern-crawl states, applies drone.choose to each in
 * order, and writes a JSON list of the chosen action strings (aligned by
 * index) to <out.json>.
 */
var fs = require('fs');
var path = require('path');
var drone = require(path.join(__dirname, 'drone.js'));

function main() {
  var args = process.argv.slice(2);
  if (args.length !== 2) {
    process.stderr.write('usage: node simulate.js <states.json> <out.json>\n');
    process.exit(2);
  }
  var states;
  try {
    states = JSON.parse(fs.readFileSync(args[0], 'utf8'));
  } catch (e) {
    process.stderr.write('cannot read states file: ' + e.message + '\n');
    process.exit(2);
  }
  var actions = [];
  if (Array.isArray(states)) {
    for (var i = 0; i < states.length; i++) {
      actions.push(drone.choose(states[i]));
    }
  }
  fs.writeFileSync(args[1], JSON.stringify(actions, null, 2) + '\n');
}

main();

/* jshint node: true, esnext: true */
/* global QUnit */
'use strict';
/* cistern-bridge: golden-test runner.
 *
 * Mirrors the project's own test/jsdom-node.js plumbing (qunit + qunit-tap,
 * jsdom window with runScripts 'dangerously' so detector tests behave as the
 * project's runner expects, the project's built dist/purify.cjs.js loaded
 * against that window) but registers only the upstream regression tests for
 * the case-preserving-attribute defect, extracted at image build time into
 * /opt/golden/cistern-suite.js from the fix commit's test/test-suite.js.
 */

global.QUnit = require('/app/src/node_modules/qunit');

const qunitTap = require('/app/src/node_modules/qunit-tap');

qunitTap(QUnit, (line) => {
  if (/^not ok/.test(line)) {
    process.exitCode = 1;
    return console.log('\n', line);
  }
  console.log(line);
});

const jsdom = require('/app/src/node_modules/jsdom');
const { JSDOM, VirtualConsole } = jsdom;
const { window } = new JSDOM(
  `<html><head></head><body><div id="qunit-fixture"></div></body></html>`,
  { runScripts: 'dangerously', virtualConsole: new VirtualConsole() }
);

const createDOMPurify = require('/app/src/dist/purify.cjs.js');
const DOMPurify = createDOMPurify(window);

window.alert = () => {
  window.xssed = true;
};

QUnit.config.autostart = false;

require('/opt/golden/cistern-suite.js')(DOMPurify, window);

QUnit.start();
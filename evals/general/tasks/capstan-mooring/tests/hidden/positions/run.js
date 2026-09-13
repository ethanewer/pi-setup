"use strict";

const rule = require(process.cwd() + "/lib/rules/no-loss-of-precision");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");

// Trailing-dot exact literals in syntactic positions the upstream regression
// test (plain declarations only) does not use: array elements, object
// values, call arguments, and inside a function body. The bug fires only
// when the integer part is all zeros (`0.` normalises to an empty
// coefficient), so each of the first three snippets carries a `0.` in a
// different position; the later entries pin that ordinary trailing-dot and
// boundary values (9007199254740994 = 2^53 + 2, exact) stay valid too.
new RuleTester().run("no-loss-of-precision", rule, {
	valid: [
		"var arr = [0., 10., 0.5];",
		"var obj = { a: 0., b: 1. };",
		"f(0., 2.);",
		"function f(a) { return a + 0.; } f(0.);",
		"var x = 3.;",
		"var y = 9007199254740994.;",
	],
	invalid: [],
});
"use strict";

const rule = require(process.cwd() + "/lib/rules/no-loss-of-precision");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");

// Trailing-dot exact literals shaped differently from the upstream test's
// inputs: unary minus (the literal token itself still ends in '.'), both
// operands of an addition, a multiplication whose second operand is written
// with a numeric separator (the rule strips '_' from the raw token before
// normalising), and a comparison. Every snippet carries a `0.` so each
// fails on the unfixed tree; the last entry is an exact non-zero control.
new RuleTester().run("no-loss-of-precision", rule, {
	valid: [
		"var x = -0.;",
		"var b = 0. + 1.;",
		"var c = 0. * 1_0.;",
		"if (0. > -1) { var ok = true; }",
		"var e = 1234567890.;",
	],
	invalid: [],
});
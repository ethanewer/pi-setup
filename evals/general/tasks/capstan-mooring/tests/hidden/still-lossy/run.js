"use strict";

const rule = require(process.cwd() + "/lib/rules/no-loss-of-precision");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");

// Same code path, opposite direction: trailing-dot literals that genuinely
// lose precision must STILL be reported after the fix (so the fix must not
// be a blanket "ignore anything with a trailing dot"). The valid controls
// pin the boundary — an element access carrying 0. stays exact, 2^53 - 1
// stays exact, while lossy values at 17 and 30 significant digits and just
// past 2^53 are reported.
new RuleTester().run("no-loss-of-precision", rule, {
	valid: [
		"var x = [0.][0];",
		"var y = 9007199254740991.;",
	],
	invalid: [
		{
			code: "var x = 9007199254740995.;",
			errors: [{ messageId: "noLossOfPrecision" }],
		},
		{
			code: "var x = 99999999999999999.;",
			errors: [{ messageId: "noLossOfPrecision" }],
		},
		{
			code: "var x = 123456789012345678901234567890.;",
			errors: [{ messageId: "noLossOfPrecision" }],
		},
	],
});
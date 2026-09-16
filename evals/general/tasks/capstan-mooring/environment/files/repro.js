"use strict";

const rule = require(process.cwd() + "/lib/rules/no-loss-of-precision");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");

new RuleTester().run("no-loss-of-precision", rule, {
	valid: ["var x = 0."],
	invalid: [
		{
			code: "var x = 9007199254740993.",
			errors: [{ messageId: "noLossOfPrecision" }],
		},
	],
});
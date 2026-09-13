"use strict";
const rule = require(process.cwd() + "/lib/rules/new-cap");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");
new RuleTester().run("new-cap", rule, {
	valid: [
		{ code: "foo[\"UTC\"]();", options: [{ properties: false }] },
		{ code: "obj[\"UTC\"](1, 2, 3);", options: [{ properties: false }] },
	],
	invalid: [],
});
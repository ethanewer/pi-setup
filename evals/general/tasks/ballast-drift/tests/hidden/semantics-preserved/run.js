"use strict";
const rule = require(process.cwd() + "/lib/rules/new-cap");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");
new RuleTester().run("new-cap", rule, {
	valid: [
		{ code: "Date.UTC(2000, 0);" },
		{ code: "Date.UTC(2000, 0);", options: [{ properties: false }] },
		{ code: "var x = foo.Bar(42);", options: [{ properties: false }] },
	],
	invalid: [
		{ code: "UTC();", options: [{ properties: false }], errors: [{ messageId: "upper" }] },
		{ code: "var x = foo.UTC();", errors: [{ messageId: "upper" }] },
	],
});
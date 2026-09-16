"use strict";
const rule = require(process.cwd() + "/lib/rules/new-cap");
const RuleTester = require(process.cwd() + "/lib/rule-tester/rule-tester");
new RuleTester().run("new-cap", rule, {
	valid: [
		{ code: "foo().UTC();", options: [{ properties: false }] },
		{ code: "var z = window.Date.UTC(2020, 0);", options: [{ properties: false }] },
		{ code: "foo?.bar.UTC();", options: [{ properties: false }] },
		{ code: "let q = build.Date.UTC(1, 2);", options: [{ properties: false }] },
		{ code: "foo?.Date.UTC();", options: [{ properties: false }] },
	],
	invalid: [],
});
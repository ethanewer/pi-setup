import { expect, test } from "bun:test";
import { promoteModel } from "../forks/pi-last-model-safe/extensions/last-model/promote.js";

test("selected model moves to the front of the scoped startup order", () => {
	const models = [
		"openrouter/deepseek/deepseek-v4-flash-0731",
		"openrouter/stealth/union-alpha",
		"openai/gpt-5.6-sol",
	];
	expect(promoteModel(models, "openrouter/stealth/union-alpha")).toEqual([
		"openrouter/stealth/union-alpha",
		"openrouter/deepseek/deepseek-v4-flash-0731",
		"openai/gpt-5.6-sol",
	]);
});

test("empty model scope remains unscoped", () => {
	expect(promoteModel(undefined, "openrouter/stealth/union-alpha")).toBeUndefined();
	expect(promoteModel([], "openrouter/stealth/union-alpha")).toEqual([]);
});

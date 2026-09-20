import { expect, test } from "bun:test";
import { promoteModel } from "../forks/pi-last-model-safe/extensions/last-model/promote.js";

test("selected model moves to the front of the scoped startup order", () => {
	const models = [
		"openrouter/deepseek/deepseek-v4-flash-0731",
		"openrouter/qwen/qwen3.8-flash",
		"openai/gpt-5.6-sol",
	];
	expect(promoteModel(models, "openrouter/qwen/qwen3.8-flash")).toEqual([
		"openrouter/qwen/qwen3.8-flash",
		"openrouter/deepseek/deepseek-v4-flash-0731",
		"openai/gpt-5.6-sol",
	]);
});

test("empty model scope remains unscoped", () => {
	expect(promoteModel(undefined, "openrouter/qwen/qwen3.8-flash")).toBeUndefined();
	expect(promoteModel([], "openrouter/qwen/qwen3.8-flash")).toEqual([]);
});

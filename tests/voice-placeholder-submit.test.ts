import { describe, expect, mock, test } from "bun:test";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

/**
 * The `[⠿ transcribing]` sentinel is a TUI artifact, not text. This pins the one place it
 * could escape the editor: a submit. Pi calls `onSubmit` from the editor's own Enter
 * handling *and* directly for Alt+Enter, so the wrapper must guard both, not `handleInput`.
 */

// The fork has no node_modules of its own; resolve the real Pi modules from Bun's global
// tree when they are there so this file cannot shadow the real key/render behaviour other
// suites in the same run depend on. Fall back to stubs only when Pi is not installed.
const bunGlobal = join(process.env.BUN_INSTALL ?? join(homedir(), ".bun"), "install/global/node_modules/@earendil-works");
const codingAgentEntry = join(bunGlobal, "pi-coding-agent/dist/index.js");
const tuiEntry = join(bunGlobal, "pi-tui/dist/index.js");
const hasPi = existsSync(codingAgentEntry);
const hasTui = existsSync(tuiEntry);

mock.module("@earendil-works/pi-coding-agent", () => (hasPi ? require(codingAgentEntry) : { CustomEditor: class {} }));
mock.module("@earendil-works/pi-tui", () =>
	hasTui
		? require(tuiEntry)
		: {
				CURSOR_MARKER: "\u0000",
				matchesKey: () => false,
				sliceByColumn: (text: string) => text,
				truncateToWidth: (text: string) => text,
				visibleWidth: (text: string) => text.length,
			},
);

const { createVoiceEditorFactory } = await import("../forks/pi-voice-stt-safe/src/ui/input-indicator");
const { placeholderText, SPINNER_SENTINEL } = await import("../forks/pi-voice-stt-safe/src/ui/transcribing");

class FakeBaseEditor {
	text = "";
	onSubmit?: (text: string) => void;
	onChange?: (text: string) => void;
	borderColor?: (str: string) => string;
	actionHandlers = new Map<string, () => void>();

	render(): string[] {
		return [this.text];
	}
	handleInput(): void {}
	invalidate(): void {}
	getText(): string {
		return this.text;
	}
	setText(text: string): void {
		this.text = text;
	}
	insertTextAtCursor(text: string): void {
		this.text += text;
	}
	getExpandedText(): string {
		return this.text;
	}
}

const fakeContext = {
	hasUI: true,
	ui: { theme: { fg: (_color: string, text: string) => text } },
} as never;

const buildEditor = (
	onParkSubmit: (text: string, submit: (text: string) => void) => boolean,
	onParkFollowUp: () => boolean = () => false,
	matches: (data: string, action: string) => boolean = (_data, action) => action === "app.message.followUp",
) => {
	const base = new FakeBaseEditor();
	const editor = createVoiceEditorFactory(
		() => base,
		{
			keybinds: ["ctrl+r"],
			profileKeybind: "ctrl+shift+p",
			ctx: fakeContext,
			getMode: () => "processing",
			getTick: () => 0,
			renderLabel: () => "",
			onToggle() {},
			onCancel() {},
			onSend() {},
			onQueue() {},
			onInsertThen() {},
			onShowProfileMenu() {},
			onParkSubmit: (_ctx: never, text: string, submit: (text: string) => void) => onParkSubmit(text, submit),
			onParkFollowUp: () => onParkFollowUp(),
			attachTui() {},
			attachKeybindings() {},
			attachEditor() {},
		},
	)({} as never, {} as never, { matches } as never);
	return { base, editor };
};

describe("voice placeholder submit guard", () => {
	test("parks a submit that still contains a placeholder instead of sending it", () => {
		const sent: string[] = [];
		let parkedText = "";
		let parkedSubmit: ((text: string) => void) | undefined;
		const { editor } = buildEditor((text, submit) => {
			parkedText = text;
			parkedSubmit = submit;
			return true;
		});

		editor.onSubmit = (text) => sent.push(text);
		editor.onSubmit(`question ${placeholderText()}`);

		expect(sent).toEqual([]);
		expect(parkedText).toBe(`question ${placeholderText()}`);
		// The original submit runs only after the transcript has replaced the marker.
		parkedSubmit?.("question spoken words");
		expect(sent).toEqual(["question spoken words"]);
	});

	test("guards the base editor too, where Pi's own Enter lands", () => {
		const sent: string[] = [];
		const { base, editor } = buildEditor(() => true);
		editor.onSubmit = (text) => sent.push(text);

		base.onSubmit?.(placeholderText());
		expect(sent).toEqual([]);
	});

	test("passes a placeholder-free submit straight through", () => {
		const sent: string[] = [];
		const { editor } = buildEditor(() => false);
		editor.onSubmit = (text) => sent.push(text);

		editor.onSubmit("just typed text");
		expect(sent).toEqual(["just typed text"]);
	});

	test("intercepts the follow-up key before Pi can queue the sentinel", () => {
		let followUps = 0;
		const { editor } = buildEditor(
			() => false,
			() => {
				followUps += 1;
				return true;
			},
		);
		editor.handleInput("alt+enter");
		expect(followUps).toBe(1);
	});

	test("passes the follow-up key through when nothing is parked", () => {
		const { editor } = buildEditor(() => false, () => false);
		// No throw, no park: the base editor receives the key as before.
		expect(() => editor.handleInput("alt+enter")).not.toThrow();
	});

	test("wraps Pi's follow-up action so a multi-key binding is guarded too", () => {
		let followUps = 0;
		let original = 0;
		// `matches` is false, so the per-keystroke fast path cannot catch it; only the wrapped
		// action handler can.
		const { base, editor } = buildEditor(
			() => false,
			() => {
				followUps += 1;
				return true;
			},
			() => false,
		);
		base.actionHandlers.set("app.message.followUp", () => {
			original += 1;
		});
		editor.handleInput("chunk");
		base.actionHandlers.get("app.message.followUp")?.();
		expect(followUps).toBe(1);
		expect(original).toBe(0);
	});

	test("the follow-up action wrap defers to Pi when nothing is parked", () => {
		let original = 0;
		const { base, editor } = buildEditor(
			() => false,
			() => false,
			() => false,
		);
		base.actionHandlers.set("app.message.followUp", () => {
			original += 1;
		});
		editor.handleInput("chunk");
		base.actionHandlers.get("app.message.followUp")?.();
		expect(original).toBe(1);
	});

	test("wrapping the follow-up action is idempotent", () => {
		let original = 0;
		const { base, editor } = buildEditor(
			() => false,
			() => false,
			() => false,
		);
		base.actionHandlers.set("app.message.followUp", () => {
			original += 1;
		});
		editor.handleInput("one");
		const wrapped = base.actionHandlers.get("app.message.followUp");
		editor.handleInput("two");

		expect(base.actionHandlers.get("app.message.followUp")).toBe(wrapped);
		wrapped?.();
		expect(original).toBe(1);
	});

	test("the sentinel is what is being guarded, not a hardcoded label", () => {
		expect(placeholderText()).toContain(SPINNER_SENTINEL);
	});
});
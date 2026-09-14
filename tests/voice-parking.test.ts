import { describe, expect, test } from "bun:test";

import { createParking } from "../forks/pi-voice-stt-safe/src/core/parked";
import { placeholderText, SPINNER_SENTINEL } from "../forks/pi-voice-stt-safe/src/ui/transcribing";

/**
 * The parked-message state machine, exercised through its hooks. These cover the two ways a
 * `[⠿ transcribing]` sentinel could survive a failed sibling in the overlapping-transcription
 * flow, which the editor-level guard alone cannot see.
 */

const makeHarness = () => {
	let editorText = "";
	let nextId = 1;
	let nextSlot = 1;
	const slots = new Set<number>();
	const pending: { id: number; intent: string; text: string; status: "pending" | "resolved" | "failed" }[] = [];
	const delivered: string[] = [];
	const notifications: string[] = [];

	const parking = createParking({
		claimSlot: () => {
			while (slots.has(nextSlot)) nextSlot += 1;
			const slot = nextSlot;
			slots.add(slot);
			return slot;
		},
		releaseSlot: (slot) => {
			slots.delete(slot);
		},
		insertMarker: (_ctx, marker) => {
			editorText += marker;
		},
		getEditorText: () => editorText,
		setEditorText: (_ctx, text) => {
			editorText = text;
		},
		rewriteEditor: (_ctx, rewrite) => {
			const next = rewrite(editorText);
			if (next.replaced) editorText = next.text;
			return next.replaced;
		},
		beginPending: (_ctx, intent, text) => {
			const id = nextId++;
			pending.push({ id, intent, text, status: "pending" });
			return id;
		},
		resolvePending: (_ctx, id) => {
			const item = pending.find((entry) => entry.id === id);
			if (item) item.status = "resolved";
		},
		failPending: (_ctx, id) => {
			const item = pending.find((entry) => entry.id === id);
			if (item) item.status = "failed";
		},
		notifyDiscarded: () => notifications.push("discarded"),
		notifyError: (_ctx, message) => notifications.push(message),
		reportError: () => {},
	});

	return {
		parking,
		ctx: {} as never,
		pending,
		delivered,
		notifications,
		getEditorText: () => editorText,
		setEditorText: (text: string) => {
			editorText = text;
		},
	};
};

describe("parked message lifecycle", () => {
	test("a submit parks the whole message, then delivers only after the transcript", () => {
		const h = makeHarness();
		h.setEditorText("hello ");
		const delivery = h.parking.beginEditorDelivery(h.ctx);

		const submitted: string[] = [];
		expect(h.parking.parkEditorSubmission(h.ctx, h.getEditorText(), (text) => submitted.push(text))).toBe(true);
		expect(h.getEditorText()).toBe("");
		expect(submitted).toEqual([]);

		delivery.resolve("world");
		expect(submitted).toEqual(["hello world"]);
	});

	test("a sibling failure does not leak the surviving sentinel or duplicate the typing", () => {
		const h = makeHarness();
		h.setEditorText("note ");
		const editorDelivery = h.parking.beginEditorDelivery(h.ctx); // note [⠿ transcribing]
		const messageDelivery = h.parking.beginMessageDelivery(h.ctx, "send", (text) => h.delivered.push(text));

		// The message batch owns both markers; the editor delivery fails first.
		editorDelivery.fail("provider timed out");
		expect(h.getEditorText()).toBe("note [⠿ transcribing 2]");

		messageDelivery.resolve("spoken");
		expect(h.getEditorText()).toBe("note spoken");
		expect(h.getEditorText()).not.toContain(SPINNER_SENTINEL);
		// The message was abandoned with the failed sibling; nothing was sent.
		expect(h.delivered).toEqual([]);
	});

	test("a surviving transcript's own failure is reported, not silently dropped", () => {
		const h = makeHarness();
		h.setEditorText("note ");
		const editorDelivery = h.parking.beginEditorDelivery(h.ctx);
		const messageDelivery = h.parking.beginMessageDelivery(h.ctx, "send", (text) => h.delivered.push(text));

		editorDelivery.fail("first failed");
		messageDelivery.fail("second failed");

		expect(h.getEditorText()).not.toContain(SPINNER_SENTINEL);
		expect(h.notifications).toContain("second failed");
	});

	test("re-parking a marker that is already in a batch does not strand that batch", () => {
		const h = makeHarness();
		const first = h.parking.beginEditorDelivery(h.ctx);
		const second = h.parking.beginEditorDelivery(h.ctx);
		const firstSubmit: string[] = [];
		h.parking.parkEditorSubmission(h.ctx, h.getEditorText(), (text) => firstSubmit.push(text));

		// A later submit names the already-parked first marker (as literal text) plus a new one.
		const third = h.parking.beginEditorDelivery(h.ctx);
		const thirdMarker = h.getEditorText();
		const secondSubmit: string[] = [];
		h.parking.parkEditorSubmission(h.ctx, `${thirdMarker}${"[⠿ transcribing]"}`, (text) => secondSubmit.push(text));

		first.resolve("one");
		second.resolve("two");
		third.resolve("three");

		// The original batch must still complete: its marker was not moved to the new batch.
		expect(firstSubmit).toEqual(["onetwo"]);
		// The literal copy of the parked marker is stripped, not delivered to the model.
		expect(secondSubmit).toEqual(["three"]);
		expect(secondSubmit[0]).not.toContain(SPINNER_SENTINEL);
	});

	test("a submit whose text is only an already-parked marker is scrubbed and sent without it", () => {
		const h = makeHarness();
		h.setEditorText("note ");
		const parked = h.parking.beginEditorDelivery(h.ctx);
		h.parking.parkEditorSubmission(h.ctx, h.getEditorText(), () => {});

		const sent: string[] = [];
		const handled = h.parking.parkEditorSubmission(h.ctx, "note [⠿ transcribing] and more", (text) => sent.push(text));

		expect(handled).toBe(true);
		expect(sent).toHaveLength(1);
		expect(sent[0]).not.toContain(SPINNER_SENTINEL);
		expect(sent[0]).toContain("and more");
		// The marker's own batch is untouched and still waiting.
		parked.resolve("spoken");
	});

	test("every copy of a reserved marker is substituted, not just the first", () => {
		const h = makeHarness();
		h.setEditorText("a ");
		const delivery = h.parking.beginEditorDelivery(h.ctx);
		// A duplicate of the same marker, as if pasted twice.
		h.setEditorText(`${h.getEditorText()} b ${placeholderText(1)}`);

		const submitted: string[] = [];
		h.parking.parkEditorSubmission(h.ctx, h.getEditorText(), (text) => submitted.push(text));
		delivery.resolve("word");

		expect(submitted).toEqual(["a word b word"]);
		expect(submitted[0]).not.toContain(SPINNER_SENTINEL);
	});

	test("a transcript that dictates its own marker substitutes once and terminates", () => {
		const h = makeHarness();
		h.setEditorText("say: ");
		const delivery = h.parking.beginEditorDelivery(h.ctx);
		const submitted: string[] = [];
		h.parking.parkEditorSubmission(h.ctx, h.getEditorText(), (text) => submitted.push(text));

		// The dictated words name the placeholder itself. That text is the user's, so it
		// travels as-is; the substitution must still happen exactly once. A scan that
		// re-read its own replacement would find the marker inside it and loop forever,
		// and the event loop is blocked for the whole loop — no timer, no Esc.
		delivery.resolve(`echo ${placeholderText(1)} back`);

		expect(submitted).toEqual([`say: echo ${placeholderText(1)} back`]);
	});
});

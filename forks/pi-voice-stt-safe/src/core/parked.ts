/**
 * Holding a composed message until every transcript placeholder inside it has landed.
 *
 * A placeholder normally lives in the editor and is replaced there. But the user can submit
 * the editor while a transcript is still in flight — Enter after stopping with the voice
 * key, or Enter while recording when the composer already held an older placeholder. The
 * sentinel must never reach the model, so the whole composed message moves above the editor,
 * every placeholder inside it is re-homed to a batch, and `deliver` runs once the last
 * transcript lands.
 *
 * The coordinator is deliberately free of Pi and config: the editor, the pending-message
 * widget, and slot accounting are all hooks, so the state machine that decides where a
 * transcript lands can be exercised on its own.
 */

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

import type { Delivery } from "./dictation-controller";
import { placeholderText, replacePlaceholder } from "../ui/transcribing";

export type ParkedBatch = {
  ctx: ExtensionContext;
  id: number;
  text: string;
  remaining: Set<string>;
  done: boolean;
  deliver(text: string): void | Promise<void>;
};

/** The mutable destination of one marker: the editor, or a parked message. */
type OpenTranscript = {
  park(batch: ParkedBatch): void;
  unpark(): void;
  /** True when this marker already belongs to a parked batch. */
  isParked(): boolean;
};

export type ParkingHooks = {
  claimSlot(): number;
  releaseSlot(slot: number): void;
  /** Insert the marker where the cursor is. */
  insertMarker(ctx: ExtensionContext, marker: string): void;
  getEditorText(ctx: ExtensionContext): string;
  setEditorText(ctx: ExtensionContext, text: string): void;
  rewriteEditor(ctx: ExtensionContext, rewrite: (text: string) => { text: string; replaced: boolean }): boolean;
  beginPending(ctx: ExtensionContext, intent: "send" | "queue", text: string): number;
  resolvePending(ctx: ExtensionContext, id: number): void;
  failPending(ctx: ExtensionContext, id: number, message: string): void;
  notifyDiscarded(ctx: ExtensionContext): void;
  notifyError(ctx: ExtensionContext, message: string): void;
  reportError(ctx: ExtensionContext, error: unknown): void;
};

export type Parking = {
  beginEditorDelivery(ctx: ExtensionContext): Delivery;
  beginMessageDelivery(
    ctx: ExtensionContext,
    outcome: "send" | "queue",
    deliver: (text: string) => void | Promise<void>,
  ): Delivery;
  parkEditorSubmission(
    ctx: ExtensionContext,
    text: string,
    submit: (text: string) => void,
    intent?: "send" | "queue",
  ): boolean;
};

export const createParking = (hooks: ParkingHooks): Parking => {
  /** Every transcript holding a placeholder, keyed by its exact marker. */
  const openTranscripts = new Map<string, OpenTranscript>();

  /**
   * A marker string is reserved for its own transcript, so every occurrence in text that is
   * being cleared or substituted goes, not just the first. A duplicate can only have come
   * from someone copying the rendered placeholder, and leaving one behind would put the
   * sentinel back on the path to the model.
   */
  const substituteAll = (text: string, replacement: string, marker: string): string => {
    let out = text;
    let replaced = true;
    while (replaced) {
      ({ text: out, replaced } = replacePlaceholder(out, replacement, marker));
    }
    return out;
  };

  /**
   * Remove the literal text of markers already owned by a parked batch. A marker string is
   * reserved: it may only ever stand in for its own transcript, so a copy that arrives in
   * some other submit — someone pasted the rendered `[⠿ transcribing]`, say — is stripped
   * rather than carried to the model. Unparked markers are left for the caller to re-home.
   */
  const scrubParkedMarkers = (text: string): string => {
    let out = text;
    for (const [marker, handle] of openTranscripts) {
      if (handle.isParked()) out = substituteAll(out, "", marker);
    }
    return out;
  };

  /** Run a submit/deliver and surface a synchronous throw or rejected promise. */
  const runSafely = (ctx: ExtensionContext, deliver: (text: string) => void | Promise<void>, text: string): void => {
    try {
      const result = deliver(text);
      if (result && typeof (result as Promise<void>).catch === "function") {
        void (result as Promise<void>).catch((error) => hooks.reportError(ctx, error));
      }
    } catch (error) {
      hooks.reportError(ctx, error);
    }
  };

  const runDelivery = (batch: ParkedBatch, text: string): void => runSafely(batch.ctx, batch.deliver, text);

  const completeParkedMarker = (batch: ParkedBatch, marker: string, replacement: string): void => {
    if (batch.done) return;
    batch.text = substituteAll(batch.text, replacement, marker);
    batch.remaining.delete(marker);
    if (batch.remaining.size > 0) return;
    batch.done = true;
    hooks.resolvePending(batch.ctx, batch.id);
    const prompt = batch.text.trim();
    if (prompt) runDelivery(batch, prompt);
  };

  /** Drop one marker and hand whatever is still outstanding back to the editor. */
  const abandonParkedBatch = (batch: ParkedBatch, marker: string, message?: string): void => {
    if (batch.done) return;
    batch.done = true;
    if (message === undefined) hooks.resolvePending(batch.ctx, batch.id);
    else hooks.failPending(batch.ctx, batch.id, message);
    batch.text = substituteAll(batch.text, "", marker);
    batch.remaining.delete(marker);
    for (const outstanding of [...batch.remaining]) openTranscripts.get(outstanding)?.unpark();
    batch.remaining.clear();
    const text = batch.text;
    if (text.trim().length === 0) return;
    const current = hooks.getEditorText(batch.ctx);
    hooks.setEditorText(batch.ctx, current.length > 0 ? `${text}${current}` : text);
  };

  const beginEditorDelivery = (ctx: ExtensionContext): Delivery => {
    const slot = hooks.claimSlot();
    const marker = placeholderText(slot);
    hooks.insertMarker(ctx, marker);

    let settled = false;
    let parked: ParkedBatch | undefined;
    const handle: OpenTranscript = {
      park(batch) {
        parked = batch;
        batch.remaining.add(marker);
      },
      unpark() {
        parked = undefined;
      },
      isParked: () => parked !== undefined,
    };
    openTranscripts.set(marker, handle);

    const settle = (): boolean => {
      if (settled) return false;
      settled = true;
      hooks.releaseSlot(slot);
      if (openTranscripts.get(marker) === handle) openTranscripts.delete(marker);
      return true;
    };

    const deliverToEditor = (replacement: string): boolean =>
      hooks.rewriteEditor(ctx, (text) => ({ text: substituteAll(text, replacement, marker), replaced: text.includes(marker) }));

    return {
      resolve: (text) => {
        if (!settle()) return;
        if (parked) {
          completeParkedMarker(parked, marker, text);
          return;
        }
        // A placeholder the user deleted while waiting means the transcript has nowhere to
        // go; appending it to whatever they typed instead would be worse than losing it.
        if (!deliverToEditor(text)) hooks.notifyDiscarded(ctx);
      },
      fail: (message) => {
        if (!settle()) return;
        if (parked) {
          abandonParkedBatch(parked, marker, message);
          return;
        }
        deliverToEditor("");
        hooks.notifyError(ctx, message);
      },
      cancel: () => {
        if (!settle()) return;
        if (parked) abandonParkedBatch(parked, marker);
        else deliverToEditor("");
      },
    };
  };

  const beginMessageDelivery = (
    ctx: ExtensionContext,
    outcome: "send" | "queue",
    deliver: (text: string) => void | Promise<void>,
  ): Delivery => {
    // Insert at the cursor first, then take the line: the transcript lands where the
    // cursor was, keeping whatever was typed on either side of it.
    const slot = hooks.claimSlot();
    const marker = placeholderText(slot);
    hooks.insertMarker(ctx, marker);
    const composed = hooks.getEditorText(ctx);
    hooks.setEditorText(ctx, "");
    // A copy of a marker already owned by another parked batch must not ride along; this
    // marker is not registered yet, so the scrub cannot touch it.
    const cleaned = scrubParkedMarkers(composed);

    const batch: ParkedBatch = {
      ctx,
      id: hooks.beginPending(ctx, outcome, cleaned),
      text: cleaned,
      remaining: new Set(),
      done: false,
      deliver,
    };

    let settled = false;
    let parked: ParkedBatch | undefined = batch;
    const handle: OpenTranscript = {
      park(next) {
        parked = next;
        next.remaining.add(marker);
      },
      unpark() {
        parked = undefined;
      },
      isParked: () => parked !== undefined,
    };
    openTranscripts.set(marker, handle);
    batch.remaining.add(marker);

    // Any placeholder already in the composer travels with the message: its transcript
    // must land in this message, not in an editor that no longer holds it.
    for (const [openMarker, openHandle] of openTranscripts) {
      if (openMarker !== marker && cleaned.includes(openMarker) && !openHandle.isParked()) openHandle.park(batch);
    }

    const settle = (): boolean => {
      if (settled) return false;
      settled = true;
      hooks.releaseSlot(slot);
      if (openTranscripts.get(marker) === handle) openTranscripts.delete(marker);
      return true;
    };

    // Once this marker has been unparked by a sibling's failure, its text is back in the
    // editor and the message it was composed into no longer exists. Rewrite the editor in
    // place, exactly as an insert delivery does, instead of restoring the frozen composed
    // text: that string still holds the failed sibling's sentinel and the original typing,
    // so restoring it would leak the sentinel and duplicate everything.
    const deliverToEditor = (replacement: string): boolean =>
      hooks.rewriteEditor(ctx, (text) => ({ text: substituteAll(text, replacement, marker), replaced: text.includes(marker) }));

    return {
      resolve: (text) => {
        if (!settle()) return;
        if (parked) {
          completeParkedMarker(parked, marker, text);
          return;
        }
        if (!deliverToEditor(text)) hooks.notifyDiscarded(ctx);
      },
      fail: (message) => {
        if (!settle()) return;
        if (parked) {
          abandonParkedBatch(parked, marker, message);
          return;
        }
        deliverToEditor("");
        // A sibling's failure already failed the batch; this transcript's own error would
        // otherwise vanish with its text, so report it too.
        hooks.notifyError(ctx, message);
      },
      cancel: () => {
        if (!settle()) return;
        if (parked) abandonParkedBatch(parked, marker);
        else deliverToEditor("");
      },
    };
  };

  /**
   * Enter pressed with a placeholder still in the editor. The model must never see the
   * sentinel, so the message is parked above the editor and the original submit runs once
   * the last transcript has replaced its marker.
   */
  const parkEditorSubmission = (
    ctx: ExtensionContext,
    text: string,
    submit: (text: string) => void,
    intent: "send" | "queue" = "send",
  ): boolean => {
    const present = [...openTranscripts.entries()].filter(([marker]) => text.includes(marker));
    if (present.length === 0) return false;

    // Literal copies of markers another parked batch already owns are stripped first, so
    // they can never be delivered as text by this batch or passed through below.
    const cleaned = scrubParkedMarkers(text);
    const unparked = present.filter(([, handle]) => !handle.isParked());
    hooks.setEditorText(ctx, "");
    if (unparked.length === 0) {
      // Nothing new to wait on: hand the scrubbed remainder straight to the caller's submit.
      if (cleaned.trim().length > 0) runSafely(ctx, submit, cleaned);
      return true;
    }

    const batch: ParkedBatch = {
      ctx,
      id: hooks.beginPending(ctx, intent, cleaned),
      text: cleaned,
      remaining: new Set(),
      done: false,
      deliver: submit,
    };
    for (const [marker] of unparked) openTranscripts.get(marker)?.park(batch);
    return true;
  };

  return { beginEditorDelivery, beginMessageDelivery, parkEditorSubmission };
};

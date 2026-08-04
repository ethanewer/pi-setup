/**
 * Resume a run that Pi compacted but then abandoned.
 *
 * The failure, observed three times on 2026-08-04 with an identical signature:
 *
 *   assistant  stopReason "length", rawStopReason "incomplete", output 16,
 *              one empty thinking block, input+cacheRead ~267,700 of a 272,000 window
 *   compaction succeeds
 *   <nothing>
 *
 * The model was truncated because the context left no room to generate. Pi has a case for
 * exactly that — `isContextOverflow` case 3, "server truncates oversized input, leaving no
 * room for output" — but it requires `usage.output === 0` AND
 * `input + cacheRead >= contextWindow * 0.99`. These messages carry 16 reasoning tokens,
 * not 0, and sat at 98.4%, just under the floor. Both conditions missed, so Pi classified
 * a truncation as a routine threshold compaction, which ends with:
 *
 *   if (willRetry) { ...; return true; }        // resume
 *   return this.agent.hasQueuedMessages();      // false -> the run is over
 *
 * So the run silently ends with its work unfinished and no error anywhere.
 *
 * That last line is also the fix. `session_compact` is emitted and awaited *before* it, so
 * anything queued during the hook makes `hasQueuedMessages()` true and Pi calls
 * `agent.continue()`. This is not a guess: in session 019fcd7f the same truncation happened
 * twice. At 16:56:38 a monitor watcher event landed 28ms after the compaction and the run
 * carried on for another 600 entries. At 18:36:39 nothing was queued and the run sat dead
 * until a human typed 64 minutes later. The monitor had accidentally rescued the first one.
 * We use the same call shape the monitor used, for the same reason.
 *
 * Deliberately narrow. It fires only when the compaction was preceded by a truncated
 * assistant message and Pi is not already going to retry, so a normal finished turn is
 * never nudged — that would make the agent chatter after every compaction.
 */

/** Cap on consecutive resumes with no successful model turn between them. */
export const MAX_CONSECUTIVE_RESUMES = 3;

export const RESUME_MESSAGE_TYPE = "context-handoff-resume";

export const RESUME_TEXT =
	"Your previous response was cut off because the context window was full — it ended " +
	"mid-reasoning with no tool call and no answer, so the work you were doing is " +
	"unfinished. The conversation has just been compacted, so there is room now. Re-read " +
	"the handoff brief above and continue from where you were interrupted.";

export const GAVE_UP_TEXT =
	`Context has been compacted ${MAX_CONSECUTIVE_RESUMES} times in a row after a truncated ` +
	"response, and each attempt was truncated again. Stopping the automatic resume so this " +
	"does not loop. Something is filling the context faster than compaction can reclaim it: " +
	"summarise your state and stop, rather than continuing to retry.";

interface AssistantLike {
	role?: string;
	stopReason?: string;
	usage?: { output?: number } | null;
}

interface EntryLike {
	message?: AssistantLike | null;
}

/**
 * True when the newest assistant message in the branch was cut off by the context limit.
 *
 * `stopReason === "length"` is the whole test. Output size is deliberately not checked:
 * requiring `output === 0` is precisely the condition that made Pi miss this, and a
 * truncation that managed to emit a few reasoning tokens first is still a truncation.
 */
export function lastAssistantWasTruncated(entries: readonly EntryLike[] | undefined): boolean {
	if (!entries) return false;
	for (let i = entries.length - 1; i >= 0; i--) {
		const message = entries[i]?.message;
		if (!message || message.role !== "assistant") continue;
		return message.stopReason === "length";
	}
	return false;
}

/** Tracks consecutive resumes so a context that cannot be reclaimed cannot spin forever. */
export class ResumeGuard {
	private consecutive = 0;

	/** Returns what to do about a compaction that followed a truncated response. */
	decide(truncated: boolean, willRetry: boolean): "resume" | "give-up" | "ignore" {
		// Pi already resumes when it will retry, and a compaction after a finished turn is
		// supposed to end the run.
		if (!truncated || willRetry) {
			this.consecutive = 0;
			return "ignore";
		}
		if (this.consecutive >= MAX_CONSECUTIVE_RESUMES) return "give-up";
		this.consecutive++;
		return "resume";
	}

	/** Called when a turn completes normally, which clears the streak. */
	noteHealthyTurn(): void {
		this.consecutive = 0;
	}

	get consecutiveResumes(): number {
		return this.consecutive;
	}
}

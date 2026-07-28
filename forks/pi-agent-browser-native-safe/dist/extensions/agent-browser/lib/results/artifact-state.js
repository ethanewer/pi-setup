/**
 * Purpose: Centralize small artifact state predicates shared by result classifiers, recommendations, and presentation.
 * Responsibilities: Identify pending recording artifacts whose output is not durable until record stop completes.
 * Scope: Artifact predicates only; verification summaries, manifests, and user-facing formatting live in neighboring modules.
 * Usage: Imported by categories, action recommendations, and presentation to avoid divergent artifact-state rules.
 * Invariants/Assumptions: `record start` / `record restart` video artifacts are pending and should not be treated like verified saved files.
 */
export function isPendingRecordingCommand(command, subcommand, kind) {
    return command === "record" && (subcommand === "start" || subcommand === "restart") && kind === "video";
}
export function isPendingRecordingArtifact(artifact) {
    return isPendingRecordingCommand(artifact.command, artifact.subcommand, artifact.kind);
}

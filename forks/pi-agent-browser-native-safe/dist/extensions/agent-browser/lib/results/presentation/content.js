/**
 * Purpose: Share small ToolPresentation content helpers used by batch and compaction code.
 * Responsibilities: Extract text/image/path fields and format batch step command labels.
 * Scope: Pure ToolPresentation content helpers only.
 */
export function isStringArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item === "string");
}
export function getPresentationText(presentation) {
    return presentation.content
        .filter((part) => part.type === "text")
        .map((part) => part.text.trim())
        .filter((text) => text.length > 0)
        .join("\n\n");
}
export function getPresentationImages(presentation) {
    return presentation.content.filter((part) => part.type === "image");
}
export function getPresentationPaths(options) {
    return options.secondaryPaths ?? (options.primaryPath ? [options.primaryPath] : []);
}
export function formatBatchStepCommand(command, index) {
    return command && command.length > 0 ? command.join(" ") : `step-${index + 1}`;
}

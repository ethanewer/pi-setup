/**
 * Purpose: Share small presentation formatting and redaction helpers across result presentation modules.
 * Responsibilities: Normalize scalar fields, stringify model-facing values, and apply sensitive-text redaction.
 * Scope: Leaf helpers only; command-family formatting lives in sibling modules.
 */
import { redactSensitiveText, redactSensitiveValue } from "../../runtime.js";
import { stringifyUnknown, truncateText } from "../text.js";
export function stringifyModelFacing(value) {
    return stringifyUnknown(redactSensitiveValue(value));
}
export function parseJsonPreviewString(value) {
    const trimmed = value.trim();
    if (!trimmed.startsWith("{") && !trimmed.startsWith("["))
        return value;
    try {
        return JSON.parse(trimmed);
    }
    catch {
        return value;
    }
}
export function redactModelFacingText(text) {
    const parsed = parseJsonPreviewString(text);
    if (parsed !== text) {
        return stringifyModelFacing(parsed);
    }
    return redactSensitiveText(text);
}
export function redactModelFacingTextIfSensitive(text) {
    return /(?:@|\b(?:access[_-]?key|api[_-]?key|auth|authorization|basic|bearer|connection[_-]?string|cookie|database[_-]?url|db[_-]?url|mongo(?:db)?[_-]?uri|pass(?:word)?|private[_-]?key|redis[_-]?url|secret|session[_-]?id|token)\b)/i.test(text)
        ? redactModelFacingText(text)
        : text;
}
export function getArrayField(data, key) {
    return Array.isArray(data[key]) ? data[key] : undefined;
}
export function getStringField(data, key) {
    const value = data[key];
    return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}
export function formatCount(count, singular, plural = `${singular}s`) {
    return `${count} ${count === 1 ? singular : plural}`;
}
export function firstLine(value, maxChars = 160) {
    return truncateText(value.split("\n", 1)[0] ?? value, maxChars);
}

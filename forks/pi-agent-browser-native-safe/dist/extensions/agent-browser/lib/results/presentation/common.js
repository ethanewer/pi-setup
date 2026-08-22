import { containsManagedSessionRestoreKey } from "../../managed-session-capabilities.js";
import { redactSensitiveText, redactSensitiveValue } from "../../runtime.js";
import { stringifyUnknown, truncateText } from "../text.js";
const UNTITLED_PAGE_SUMMARY = "(untitled page)";
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
    return containsManagedSessionRestoreKey(text) || /(?:@|\b(?:access[_-]?key|api[_-]?key|auth|authorization|basic|bearer|connection[_-]?string|cookie|database[_-]?url|db[_-]?url|mongo(?:db)?[_-]?uri|pass(?:word)?|private[_-]?key|redis[_-]?url|secret|session[_-]?id|token)\b)/i.test(text)
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
// `lifecycle` is upstream launch/reuse bookkeeping, never page content, so it must not be the
// answer an agent reads when a command has no dedicated presenter.
export function omitUpstreamLifecycle(data) {
    const { lifecycle: _lifecycle, ...rest } = data;
    return rest;
}
export function getPageSummary(data) {
    const title = typeof data.title === "string" ? data.title : undefined;
    const url = typeof data.url === "string" ? data.url : undefined;
    if (title === undefined && url === undefined)
        return undefined;
    if (title && url)
        return `${title}\n${url}`;
    if (url)
        return url;
    return title || UNTITLED_PAGE_SUMMARY;
}
export function formatCount(count, singular, plural = `${singular}s`) {
    return `${count} ${count === 1 ? singular : plural}`;
}
export function firstLine(value, maxChars = 160) {
    return truncateText(value.split("\n", 1)[0] ?? value, maxChars);
}

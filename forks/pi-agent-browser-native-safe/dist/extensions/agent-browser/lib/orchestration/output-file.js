import { mkdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";
import { isRecord } from "../parsing.js";
function normalizeRequestedOutputPath(path) {
    return path.startsWith("@") ? path.slice(1) : path;
}
function getTextContent(result) {
    return result.content
        ?.filter((item) => item.type === "text")
        .map((item) => item.text)
        .join("\n\n") ?? "";
}
function getOutputPayload(result) {
    const details = isRecord(result.details) ? result.details : undefined;
    if (details && details.data !== undefined)
        return { source: "details.data", value: details.data };
    return { source: "content.text", value: getTextContent(result) };
}
function serializeOutputPayload(value) {
    return typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`;
}
function appendOutputFileNotice(result, message) {
    const content = [...(result.content ?? [])];
    if (content[0]?.type === "text") {
        content[0] = { ...content[0], text: `${content[0].text}\n\n${message}` };
        return content;
    }
    return [{ type: "text", text: message }, ...content];
}
export async function applyAgentBrowserOutputPath(options) {
    if (!options.outputPath)
        return options.result;
    if (options.result.isError || (isRecord(options.result.details) && options.result.details.resultCategory === "failure"))
        return options.result;
    const requestedPath = normalizeRequestedOutputPath(options.outputPath);
    const absolutePath = isAbsolute(requestedPath) ? requestedPath : resolve(options.cwd, requestedPath);
    const payload = getOutputPayload(options.result);
    try {
        const serialized = serializeOutputPayload(payload.value);
        await mkdir(dirname(absolutePath), { recursive: true });
        await writeFile(absolutePath, serialized, "utf8");
        const bytes = Buffer.byteLength(serialized, "utf8");
        const outputFile = { absolutePath, bytes, path: requestedPath, source: payload.source, status: "saved" };
        const details = isRecord(options.result.details) ? { ...options.result.details, outputFile } : { outputFile };
        return {
            ...options.result,
            content: options.preserveTextContent ? options.result.content : appendOutputFileNotice(options.result, `Output file: ${requestedPath} (${bytes} bytes from ${payload.source}).`),
            details,
        };
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const outputFile = { absolutePath, error: message, path: requestedPath, source: payload.source, status: "failed" };
        const details = isRecord(options.result.details)
            ? (() => {
                const rest = { ...options.result.details };
                delete rest.successCategory;
                return { ...rest, failureCategory: rest.failureCategory ?? "upstream-error", outputFile, resultCategory: "failure" };
            })()
            : { failureCategory: "upstream-error", outputFile, resultCategory: "failure" };
        return {
            ...options.result,
            content: options.preserveTextContent ? options.result.content : appendOutputFileNotice(options.result, `Output file failed: ${requestedPath} (${message}).`),
            details,
            isError: true,
        };
    }
}

export function isRecord(value) {
    return typeof value === "object" && value !== null;
}
export function parsePositiveInteger(rawValue) {
    if (typeof rawValue !== "string")
        return undefined;
    const normalizedValue = rawValue.trim();
    if (!/^\d+$/.test(normalizedValue))
        return undefined;
    const parsedValue = Number(normalizedValue);
    if (!Number.isSafeInteger(parsedValue) || parsedValue <= 0)
        return undefined;
    return parsedValue;
}

/**
 * Purpose: Build compact JSON-schema string enums without importing pi runtime helpers.
 * Responsibilities: Mirror pi-ai StringEnum's `{ type: "string", enum: [...] }` shape while keeping extension startup imports light.
 * Scope: Schema construction only.
 */
import { JsonSchema } from "./json-schema.js";
export function StringEnum(values, options) {
    return JsonSchema.Unsafe({
        type: "string",
        enum: [...values],
        ...options,
    });
}

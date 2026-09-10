// schemas.ts — the single source of truth for the catalogue API.
// The same zod schemas drive request validation (routes) and the emitted
// OpenAPI 3 document (scripts/generate-openapi.ts), so the two cannot drift.
import { z } from "zod";
import { extendZodWithOpenApi } from "@asteasolutions/zod-to-openapi";

// The OpenAPI generator must decorate the zod classes before any schema is
// built, so the schemas below can carry the metadata the generator reads.
extendZodWithOpenApi(z);

export const MEDIUMS = ["film", "series", "documentary", "short"] as const;
export type Medium = (typeof MEDIUMS)[number];

export const mediumSchema = z.enum(MEDIUMS);

// A catalogued work as stored and returned. `id` is server-assigned only.
export const mediaItemSchema = z.object({
  id: z.number().int().positive(),
  title: z.string().min(1).max(100),
  year: z.number().int().min(1900).max(2100),
  rating: z.number().int().min(0).max(100),
  medium: mediumSchema,
  tags: z.array(z.string().min(1).max(40)).max(5),
});
export type MediaItem = z.infer<typeof mediaItemSchema>;

// Payload accepted by POST /api/media. Unknown top-level fields are rejected.
export const mediaCreateSchema = z
  .object({
    title: z.string().min(1).max(100),
    year: z.number().int().min(1900).max(2100),
    rating: z.number().int().min(0).max(100),
    medium: mediumSchema,
    tags: z.array(z.string().min(1).max(40)).max(5).optional().default([]),
  })
  .strict();
export type MediaCreate = z.infer<typeof mediaCreateSchema>;

// Payload accepted by PATCH /api/media/:id. Partial, at least one known
// field, and no unknown fields.
export const mediaUpdateSchema = z
  .object({
    title: z.string().min(1).max(100),
    year: z.number().int().min(1900).max(2100),
    rating: z.number().int().min(0).max(100),
    medium: mediumSchema,
    tags: z.array(z.string().min(1).max(40)).max(5),
  })
  .partial()
  .strict()
  .refine((v) => Object.keys(v ?? {}).length > 0, {
    message: "patch body must contain at least one known field",
    path: [],
  });
export type MediaUpdate = z.infer<typeof mediaUpdateSchema>;

// Query contract for GET /api/media (cursor-paginated).
export const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).max(300).optional(),
});
export type ListQuery = z.infer<typeof listQuerySchema>;

// Path parameter contract for /api/media/:id.
export const idParamSchema = z.object({
  id: z.string().regex(/^[1-9][0-9]*$/, "id must be a positive integer"),
});

// Uniform error envelope for every non-2xx response.
export const apiErrorSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    details: z
      .array(
        z.object({
          path: z.array(z.union([z.string(), z.number()])),
          code: z.string(),
          message: z.string(),
        })
      )
      .optional(),
  }),
});
export type ApiError = z.infer<typeof apiErrorSchema>;

export function validationFailed(details: unknown[]): ApiError {
  return {
    error: {
      code: "validation_failed",
      message: "request validation failed",
      details: details as ApiError["error"]["details"],
    },
  };
}

export function notFound(message = "resource not found"): ApiError {
  return { error: { code: "not_found", message } };
}

export function badRequest(message: string): ApiError {
  return { error: { code: "bad_request", message } };
}
// scripts/generate-openapi.ts — emits /app/openapi.json from the zod schemas
// via @asteasolutions/zod-to-openapi, so the document and the validation logic
// share one source of truth. Run as: node dist/scripts/generate-openapi.js
import { writeFileSync } from "fs";
import path from "path";
import { z } from "zod";
import { OpenAPIGenerator, OpenAPIRegistry } from "@asteasolutions/zod-to-openapi";
import {
  apiErrorSchema,
  idParamSchema,
  listQuerySchema,
  mediaCreateSchema,
  mediaItemSchema,
  mediaUpdateSchema,
} from "../src/schemas";

const registry = new OpenAPIRegistry();

registry.register("Medium", z.enum(["film", "series", "documentary", "short"]));
registry.register("MediaItem", mediaItemSchema);
registry.register("MediaCreate", mediaCreateSchema);
registry.register("MediaUpdate", mediaUpdateSchema);
registry.register("ApiError", apiErrorSchema);

const errContent = {
  "application/json": { schema: apiErrorSchema },
};

// ---- GET /api/media (cursor-paginated list) ---------------------------------
registry.registerPath({
  method: "get",
  path: "/api/media",
  summary: "List the catalogue with cursor pagination",
  description:
    "Items ordered by year ascending then id ascending. The response's " +
    "next_cursor marks the last delivered item; send it back verbatim as the " +
    "cursor query parameter to fetch the next page, and a value of null means " +
    "the end of the list.",
  request: { query: listQuerySchema },
  responses: {
    200: {
      description: "One page of catalogue entries",
      content: {
        "application/json": {
          schema: z.object({
            items: z.array(mediaItemSchema),
            next_cursor: z.string().nullable(),
            total: z.number().int(),
          }),
        },
      },
    },
    400: { description: "Invalid or malformed query parameters", content: errContent },
  },
  tags: ["catalogue"],
});

// ---- POST /api/media (create) ------------------------------------------------
registry.registerPath({
  method: "post",
  path: "/api/media",
  summary: "Create a catalogue entry",
  request: {
    body: {
      description: "Catalogue entry; unknown fields are rejected",
      content: { "application/json": { schema: mediaCreateSchema } },
      required: true,
    },
  },
  responses: {
    201: {
      description: "The created entry, with its server-assigned id",
      content: { "application/json": { schema: z.object({ item: mediaItemSchema }) } },
    },
    400: { description: "Validation failed", content: errContent },
  },
  tags: ["catalogue"],
});

// ---- GET /api/media/{id} ----------------------------------------------------
registry.registerPath({
  method: "get",
  path: "/api/media/{id}",
  summary: "Fetch one catalogue entry by id",
  request: { params: idParamSchema },
  responses: {
    200: {
      description: "The requested entry",
      content: { "application/json": { schema: z.object({ item: mediaItemSchema }) } },
    },
    400: { description: "id is not a positive integer", content: errContent },
    404: { description: "No entry with that id exists", content: errContent },
  },
  tags: ["catalogue"],
});

// ---- PATCH /api/media/{id} ----------------------------------------------------
registry.registerPath({
  method: "patch",
  path: "/api/media/{id}",
  summary: "Partially update a catalogue entry",
  request: {
    params: idParamSchema,
    body: {
      description: "Any subset of the entry fields (at least one)",
      content: { "application/json": { schema: mediaUpdateSchema } },
      required: true,
    },
  },
  responses: {
    200: {
      description: "The updated entry",
      content: { "application/json": { schema: z.object({ item: mediaItemSchema }) } },
    },
    400: { description: "Validation failed", content: errContent },
    404: { description: "No entry with that id exists", content: errContent },
  },
  tags: ["catalogue"],
});

const generator = new OpenAPIGenerator(registry.definitions, "3.0.3");
const document = generator.generateDocument({
  info: {
    title: "Media Catalogue API",
    version: "1.0.0",
    description:
      "REST API for a media catalogue. Every request and response is JSON. " +
      "Validation failures return HTTP 400 with an error envelope carrying " +
      "per-field details; unknown ids return 404.",
  },
});

const target = path.join(__dirname, "..", "..", "openapi.json");
writeFileSync(target, JSON.stringify(document, null, 2) + "\n");
console.log(`wrote ${target}`);
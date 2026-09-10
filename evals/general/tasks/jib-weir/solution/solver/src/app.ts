// app.ts — the Express application: four catalogue endpoints, a health check
// for readiness probing, the emitted OpenAPI document at /openapi.json, and a
// uniform JSON error envelope for every failure (400/404/500).
import express, { type ErrorRequestHandler } from "express";
import { readFileSync } from "fs";
import type { ZodType, ZodTypeDef } from "zod";
import { MediaStore } from "./store";
import {
  badRequest,
  idParamSchema,
  listQuerySchema,
  mediaCreateSchema,
  mediaUpdateSchema,
  notFound,
  validationFailed,
  type ApiError,
} from "./schemas";
import type { MediaCreate } from "./schemas";

function validate<T>(schema: ZodType<T, ZodTypeDef, unknown>, value: unknown, res: express.Response): T | null {
  const parsed = schema.safeParse(value);
  if (parsed.success) {
    return parsed.data as T;
  }
  const details = parsed.error.issues.map((issue) => ({
    path: issue.path,
    code: issue.code,
    message: issue.message,
  }));
  sendError(res, 400, validationFailed(details));
  return null;
}

function sendError(res: express.Response, status: number, body: ApiError) {
  res.status(status).json(body);
}

export function createApp(seed: MediaCreate[], openapiDoc: Buffer) {
  const store = new MediaStore(seed);
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json());

  // ---- GET /api/media : cursor-paginated list -------------------------------
  app.get("/api/media", (req, res) => {
    const query = validate(listQuerySchema, req.query, res);
    if (!query) return;
    let page;
    try {
      page = store.list(query.limit, query.cursor);
    } catch {
      sendError(res, 400, {
        error: {
          code: "validation_failed",
          message: "malformed cursor",
          details: [{ path: ["cursor"], code: "invalid_string", message: "cursor does not decode" }],
        },
      });
      return;
    }
    res.json(page);
  });

  // ---- POST /api/media : create -------------------------------------------------
  app.post("/api/media", (req, res) => {
    const body = validate(mediaCreateSchema, req.body, res);
    if (!body) return;
    const item = store.add(body);
    res.status(201).json({ item });
  });

  // ---- GET /api/media/:id : fetch one ----------------------------------------
  app.get("/api/media/:id", (req, res) => {
    const params = validate(idParamSchema, { id: req.params.id }, res);
    if (!params) return;
    const item = store.get(Number(params.id));
    if (!item) {
      sendError(res, 404, notFound(`media id ${params.id} not found`));
      return;
    }
    res.json({ item });
  });

  // ---- PATCH /api/media/:id : partial update -------------------------------------
  app.patch("/api/media/:id", (req, res) => {
    const params = validate(idParamSchema, { id: req.params.id }, res);
    if (!params) return;
    const body = validate(mediaUpdateSchema, req.body, res);
    if (!body) return;
    const item = store.update(Number(params.id), body);
    if (!item) {
      sendError(res, 404, notFound(`media id ${params.id} not found`));
      return;
    }
    res.json({ item });
  });

  // ---- infrastructure ---------------------------------------------------------
  app.get("/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  app.get("/openapi.json", (_req, res) => {
    res.type("application/json").send(openapiDoc);
  });

  // Malformed JSON bodies must still get the uniform envelope, not Express's
  // default HTML 400.
  const jsonErrorHandler: ErrorRequestHandler = (err, _req, res, next) => {
    if (err instanceof SyntaxError && (err as { status?: number }).status === 400) {
      sendError(res, 400, badRequest("malformed JSON body"));
      return;
    }
    next(err);
  };
  app.use(jsonErrorHandler);

  // Last-resort 500 so failures are never empty responses.
  const finalHandler: ErrorRequestHandler = (err, _req, res, _next) => {
    console.error("unhandled error", err);
    sendError(res, 500, { error: { code: "internal", message: "internal server error" } });
  };
  app.use(finalHandler);

  return app;
}
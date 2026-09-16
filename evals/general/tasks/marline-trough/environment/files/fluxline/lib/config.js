// config.js — load and validate a fluxline normalization config.
//
// Config schema (JSON):
//
//   {
//     "scales": { "<sensor>": <int multiplier>, ... },
//     "drops":  [ { "sensor": "<sensor>", "below": <int> | "above": <int> }, ... ],
//     "emit":   [ "<key>", ... ]            // ordered output keys; "value" is derived
//   }
//
// Validation is strict: a malformed config aborts the run with exit code 2.

import { readFile } from "node:fs/promises";

export async function loadConfig(path) {
  let text;
  try {
    text = await readFile(path, "utf8");
  } catch (err) {
    throw new Error(`cannot read config ${path}: ${err.message}`);
  }
  let cfg;
  try {
    cfg = JSON.parse(text);
  } catch (err) {
    throw new Error(`config ${path} is not valid JSON: ${err.message}`);
  }
  validate(cfg);
  return cfg;
}

function validate(cfg) {
  if (!cfg || typeof cfg !== "object" || Array.isArray(cfg)) {
    throw new Error("config must be a JSON object");
  }
  if (!cfg.scales || typeof cfg.scales !== "object" || Array.isArray(cfg.scales)) {
    throw new Error('config requires a "scales" object mapping sensor -> integer multiplier');
  }
  for (const [sensor, mult] of Object.entries(cfg.scales)) {
    if (!Number.isInteger(mult)) {
      throw new Error(`scale for sensor "${sensor}" must be an integer`);
    }
  }
  if (cfg.drops !== undefined) {
    if (!Array.isArray(cfg.drops)) {
      throw new Error('config "drops" must be an array of rules');
    }
    for (const rule of cfg.drops) {
      if (!rule || typeof rule !== "object" || typeof rule.sensor !== "string") {
        throw new Error('each drop rule needs {"sensor": "..", "below"|"above": int}');
      }
      if (rule.below !== undefined && !Number.isInteger(rule.below)) {
        throw new Error(`drop rule for "${rule.sensor}": "below" must be an integer`);
      }
      if (rule.above !== undefined && !Number.isInteger(rule.above)) {
        throw new Error(`drop rule for "${rule.sensor}": "above" must be an integer`);
      }
      if (rule.below === undefined && rule.above === undefined) {
        throw new Error(`drop rule for "${rule.sensor}" needs "below" or "above"`);
      }
    }
  } else {
    cfg.drops = [];
  }
  if (!Array.isArray(cfg.emit) || cfg.emit.length === 0) {
    throw new Error('config requires a non-empty "emit" key list');
  }
  for (const key of cfg.emit) {
    if (typeof key !== "string") {
      throw new Error('every "emit" entry must be a string key');
    }
  }
}
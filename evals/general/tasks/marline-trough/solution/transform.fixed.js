// transform.js — the row normalization stage of the fluxline pipeline.
//
// enrich(rec, cfg) applies the config rules to one input record and returns
// the normalized output record, or null when the record must be dropped.
//
// transform(lines, cfg) is an async generator: it consumes the line source
// lazily, one record at a time, and yields each normalized record the moment
// it is ready. Nothing is accumulated between rows, so the working set stays
// bounded no matter how large the input is. The caller drives the write side,
// which applies its own backpressure through the output stream.

/**
 * Normalize one parsed input record against `cfg`.
 *
 * @param {object} rec  parsed NDJSON row ({ts, sensor, raw, site, ...})
 * @param {object} cfg  validated fluxline config
 * @returns {Promise<object|null>}
 */
export async function enrich(rec, cfg) {
  const scale = cfg.scales[rec.sensor];
  if (scale === undefined) {
    return null; // unknown sensor: not a metric this pipeline tracks
  }
  const value = rec.raw * scale;
  for (const rule of cfg.drops) {
    if (rule.sensor !== rec.sensor) continue;
    if (rule.below !== undefined && value < rule.below) return null;
    if (rule.above !== undefined && value > rule.above) return null;
  }
  const out = {};
  for (const key of cfg.emit) {
    if (key === "value") {
      out.value = value;
    } else if (rec[key] === undefined) {
      return null; // emit key missing from the input row: not normalizeable
    } else {
      out[key] = rec[key];
    }
  }
  return out;
}

/**
 * Transform a line source into normalized records.
 *
 * @param {AsyncIterable<string>} lines  lazily-yielded input lines
 * @param {object} cfg                   validated fluxline config
 * @yields {object} normalized records in input order
 */
export async function* transform(lines, cfg) {
  for await (const raw of lines) {
    const text = raw.trim();
    if (text.length === 0) continue;
    let rec;
    try {
      rec = JSON.parse(text);
    } catch {
      continue; // malformed line: not NDJSON, skip it
    }
    const row = await enrich(rec, cfg);
    if (row !== null) yield row;
  }
}

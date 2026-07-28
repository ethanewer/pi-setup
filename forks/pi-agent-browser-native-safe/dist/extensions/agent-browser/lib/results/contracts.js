/**
 * Purpose: Define stable result-rendering data contracts shared across focused result modules.
 * Responsibilities: Keep upstream envelope, presentation, artifact, category, and network shapes in one type-only surface.
 * Scope: Types only; runtime classifiers, manifests, network rules, and text helpers live in neighboring modules.
 * Usage: Imported with `import type` by result modules and re-exported by the public results facade.
 * Invariants/Assumptions: This file has no runtime policy so adding fields cannot hide behavior in a catch-all module.
 */
export {};

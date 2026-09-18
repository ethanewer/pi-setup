import { WorkflowAuthoringProtection } from "./enums.js";
/** Exact installed guidance location retained for an authoring surface without model evidence. */
export interface ProtectedGuidanceSurface {
    path: string;
    anchor?: string;
    requiredText?: string;
}
/** Evidence and optimization policy for one stable workflow authoring surface. */
export interface WorkflowAuthoringCoverageEntry {
    id: string;
    kind: string;
    reference: {
        path: string;
        anchor?: string;
    };
    example?: string;
    behaviorEvidence: readonly string[];
    comprehensionScenarios: readonly string[];
    protection: WorkflowAuthoringProtection;
    protectedGuidance: readonly ProtectedGuidanceSurface[];
}
/** Scenario identifiers that release checks may accept as provider-backed evidence. */
export declare const WORKFLOW_COMPREHENSION_SCENARIO_IDS: string[];
/** Mixed guidance files that require explicit acceptance while behavioral coverage remains partial. */
export declare const WORKFLOW_AUTHORING_FROZEN_FILES: readonly [{
    readonly path: "skills/workflow-authoring/SKILL.md";
    readonly sha256: "a5a250aaf6d211a1c318a4f2e69e7b119d51d13b983e7fa79ffed450cf68da4e";
}, {
    readonly path: "skills/workflow-authoring/references/runtime.md";
    readonly sha256: "bdd52db13dba83660f50cc151f9e8b9a71a465e322907d91db9c7be4164f24b9";
}, {
    readonly path: "skills/workflow-authoring/references/helpers.md";
    readonly sha256: "1c8d253649f00412511f17ffc08c6156797b99de72ae037e14f2ea92ac33a11e";
}, {
    readonly path: "skills/workflow-authoring/references/specialized-helpers.md";
    readonly sha256: "8cf78fe0285fecd65e1a80626f29ff8c3b4977f65c7370cc1d3511ff6eda4305";
}, {
    readonly path: "skills/workflow-authoring/references/lifecycle.md";
    readonly sha256: "e5f75ae16944a58f16278a70cc0e5130590ef5747ce315a89ff58aab6669d43e";
}, {
    readonly path: "skills/workflow-authoring/references/pattern-selection.md";
    readonly sha256: "923988a1b4d506a7b330bf5e4b8ab47cf8456edcfe6674b5d8d8848264633c3d";
}, {
    readonly path: "skills/workflow-authoring/references/focused-recipes.md";
    readonly sha256: "8cdacc3e659c2ce7bab7f73a311dc0d94ce1df5ed6fc7c66515e73e1bb8b157e";
}, {
    readonly path: "skills/workflow-authoring/references/registry-ownership.md";
    readonly sha256: "dd655f994e8bd92e662586a078e3692eacc1782b934e098e5781121763e3da3e";
}, {
    readonly path: "skills/workflow-authoring/references/review.md";
    readonly sha256: "323e22167f2615dd1fbb1a3e457339ac31f3c04fd545519dce4bbc0040baec51";
}, {
    readonly path: "skills/workflow-authoring/references/debugging.md";
    readonly sha256: "781d70be77a0d635e385d6f6ff6afeb9dee05e3e679e5d991bb9e47b9822a402";
}, {
    readonly path: "skills/workflow-authoring/examples/classify-and-act.js";
    readonly sha256: "23d0d9f37ee8648cd29ca526b0b23cf55bd3ac57efd02e1b93e227bcd0c18603";
}, {
    readonly path: "skills/workflow-authoring/examples/tournament.js";
    readonly sha256: "3a90bd3055c5e38e13fd8d7447173fc2e6a141fbc33b9bcc8a84723b7ab9d2e6";
}, {
    readonly path: "skills/workflow-authoring/examples/validated-gate.js";
    readonly sha256: "1cb4b3941ae61ebd1e12ada899f7d04678fe858a307c7fabc408603a4b9ba889";
}];
/** Stable orchestration-pattern identifiers covered by the authoring inventory. */
export declare const WORKFLOW_AUTHORING_PATTERN_IDS: readonly ["workflow.pattern.classify-and-act", "workflow.pattern.fan-out-and-synthesize", "workflow.pattern.adversarial-verification", "workflow.pattern.generate-and-filter", "workflow.pattern.tournament", "workflow.pattern.loop-until-done"];
/** Stable focused-recipe identifiers covered by the authoring inventory. */
export declare const WORKFLOW_AUTHORING_RECIPE_IDS: readonly ["workflow.recipe.phased-budgets", "workflow.recipe.saved-nested-workflows", "workflow.recipe.bounded-semantic-retry", "workflow.recipe.validator-feedback", "workflow.recipe.structured-output"];
/** Complete release-gated inventory of behavioral coverage and frozen authoring guidance. */
export declare const WORKFLOW_AUTHORING_COVERAGE: readonly WorkflowAuthoringCoverageEntry[];

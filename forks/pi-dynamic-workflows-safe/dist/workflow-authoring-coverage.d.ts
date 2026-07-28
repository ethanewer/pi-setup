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
    readonly sha256: "62b92fda97f86e54bbb5d399b8a796359f0c4ca3ade5579a2f9028fcd678a4ef";
}, {
    readonly path: "skills/workflow-authoring/references/runtime.md";
    readonly sha256: "14f1c4496c523d2e37316a7c96041a22630a65d342d08fdd77aeca2d325e22a3";
}, {
    readonly path: "skills/workflow-authoring/references/helpers.md";
    readonly sha256: "1c8d253649f00412511f17ffc08c6156797b99de72ae037e14f2ea92ac33a11e";
}, {
    readonly path: "skills/workflow-authoring/references/specialized-helpers.md";
    readonly sha256: "7597c94bbacea885697fb2d05a96ed9ec39403ca6d3a94547bf8ce5e233b2c76";
}, {
    readonly path: "skills/workflow-authoring/references/lifecycle.md";
    readonly sha256: "ec3b851066b55c716362553d99680ba7a00275551750586c4fa74f603342ac62";
}, {
    readonly path: "skills/workflow-authoring/references/pattern-selection.md";
    readonly sha256: "923988a1b4d506a7b330bf5e4b8ab47cf8456edcfe6674b5d8d8848264633c3d";
}, {
    readonly path: "skills/workflow-authoring/references/focused-recipes.md";
    readonly sha256: "30906054232f67029e31f71b3b093f9949f6de9116e4381f433009c401f2c5c7";
}, {
    readonly path: "skills/workflow-authoring/references/registry-ownership.md";
    readonly sha256: "daf324448be16732c6796fd6359d1b1b842fa550ed616a6154f556d6ec1ef0b9";
}, {
    readonly path: "skills/workflow-authoring/references/review.md";
    readonly sha256: "2bd97acb87a8f6e9514892cdf5c431305b3d8952ba9761c1c203c217b08c9e7d";
}, {
    readonly path: "skills/workflow-authoring/references/debugging.md";
    readonly sha256: "2938e635f5856f2934e42c9cc3b7035a66d53176f4ab2beadfeabb9abf42e6cc";
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

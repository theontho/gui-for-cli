import { runActionTestStep } from "./bundle-test-action-step.js";
import { runSetupTestStep } from "./bundle-test-setup-step.js";

export async function runBundleTestStep(step, index, totalSteps, manifest, workspaceRoot, runtime, options) {
    switch (step.kind) {
        case "setup":
            return runSetupTestStep(step, index, totalSteps, manifest, workspaceRoot, options);
        case "action":
            return runActionTestStep(step, index, manifest, workspaceRoot, runtime, options);
        default:
            throw new Error(`Unsupported bundle test step kind: ${step.kind}`);
    }
}

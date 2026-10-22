import { checkedOptionsForContext } from "../../../shared/rendering.js";
import { runDataSource } from "./action-runner.js";
import { errorMessage } from "./errors.js";
import { resolveDataSource } from "./manifest-lookup.js";
import { resolvePlatformScriptPath } from "./platform-scripts.js";
import { expandInputs } from "./bundle-test-runtime.js";
import { makeReport, outputExpectationFailure } from "./bundle-test-report.js";
import type { BundleManifest, CommandContext } from "../../../shared/types.js";
import type { BundleTestRuntime, BundleTestStep, BundleTestStepOptions, BundleTestStepReport } from "./bundle-test-types.js";

/** Loads a control's (or config setting's) data source the way the app does when
 *  it shows the page, and checks what it returns: the script must resolve for
 *  this platform, exit 0, print JSON, and offer at least `minimumOptions`. */
export async function runDataSourceTestStep(
    step: BundleTestStep,
    index: number,
    manifest: BundleManifest,
    workspaceRoot: string,
    runtime: BundleTestRuntime,
    options: BundleTestStepOptions,
): Promise<BundleTestStepReport> {
    const started = new Date();
    try {
        if (!step.pageID || !step.sectionID || !step.controlID) {
            throw new Error("Data source steps must include pageID, sectionID and controlID.");
        }
        const dataSource = resolveDataSource(manifest, {
            pageID: step.pageID,
            sectionID: step.sectionID,
            controlID: step.controlID,
            ...(step.settingID ? { settingID: step.settingID } : {}),
        });
        const command = await resolvePlatformScriptPath(String(dataSource.path), workspaceRoot);
        options.emit({ type: "message", text: `$ ${command} (data source)` });
        if (options.dryRun) {
            return makeReport(step, index, started, "skipped", { command });
        }
        const payload = await runDataSource(dataSource, stepContext(step, runtime.context, workspaceRoot), workspaceRoot, options.runProcess);
        const output = JSON.stringify(payload);
        options.emit({ type: "command-output", text: `${output}\n` });
        const offered = payload.options?.length ?? 0;
        const minimum = step.minimumOptions ?? 0;
        const error = offered < minimum
            ? `Expected at least ${minimum} options but the data source offered ${offered}.`
            : outputExpectationFailure(output, step);
        return makeReport(step, index, started, error ? "failed" : "passed", { command, exitCode: 0, output, error });
    }
    catch (error) {
        return makeReport(step, index, started, "failed", { error: errorMessage(error) });
    }
}

function stepContext(step: BundleTestStep, base: CommandContext, workspaceRoot: string): CommandContext {
    const inputs = expandInputs(step.inputs ?? {}, workspaceRoot);
    return {
        ...base,
        fieldValues: { ...base.fieldValues, ...(inputs.fieldValues ?? {}) },
        configValues: { ...base.configValues, ...(inputs.configValues ?? {}) },
        checkedOptions: { ...base.checkedOptions, ...checkedOptionsForContext(inputs.checkedOptions ?? {}) },
    };
}

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { shellQuote } from "../../../shared/rendering.js";
import type { LooseRecord } from "../../../shared/types.js";

export async function writeBundleTestReport(report, reportPath) {
    const outputPath = path.resolve(reportPath ?? defaultReportPath());
    await mkdir(path.dirname(outputPath), { recursive: true });
    await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    return outputPath;
}

export function outputExpectationFailure(output, step) {
    const failures: string[] = [];
    for (const required of step.requiredOutput ?? []) {
        if (!output.includes(required)) {
            failures.push(`Required output was not found: ${required}`);
        }
    }
    for (const forbidden of step.forbiddenOutput ?? []) {
        if (output.includes(forbidden)) {
            failures.push(`Forbidden output was found: ${forbidden}`);
        }
    }
    return failures.length ? failures.join(" ") : null;
}

export function makeReport(step, index, started, status: string, values: LooseRecord = {}) {
    const finished = new Date();
    return {
        index,
        id: step.id,
        kind: step.kind,
        actionID: values.actionID ?? step.actionID,
        status,
        command: values.command,
        exitCode: values.exitCode,
        timedOut: Boolean(values.timedOut ?? false),
        startedAt: started.toISOString(),
        finishedAt: finished.toISOString(),
        durationSeconds: (finished.getTime() - started.getTime()) / 1000,
        output: String(values.output ?? ""),
        error: values.error == null ? null : String(values.error),
    };
}

export function skippedReport(step, index, reason) {
    const now = new Date();
    return {
        index,
        id: step.id,
        kind: step.kind,
        actionID: step.actionID,
        status: "skipped",
        startedAt: now.toISOString(),
        finishedAt: now.toISOString(),
        durationSeconds: 0,
        output: "",
        error: reason,
    };
}

export function emitStepFinished(report, totalSteps, emit) {
    let message = `Step ${report.index}/${totalSteps} ${report.status} in ${report.durationSeconds.toFixed(1)}s`;
    if (report.exitCode != null) {
        message += ` (exit ${report.exitCode})`;
    }
    if (report.error) {
        message += `: ${report.error}`;
    }
    emit({ type: "message", text: message });
}

export function stepDescription(step) {
    if (step.kind === "setup") {
        return step.id ? `setup ${step.id}` : "setup";
    }
    const identifier = step.actionID ?? step.id ?? "action";
    return step.pageID ? `action ${identifier} on ${step.pageID}` : `action ${identifier}`;
}

export function setupCommandSummary(count) {
    return `bundle setup (${count} step${count === 1 ? "" : "s"})`;
}

export function commandLine(executable, args) {
    return [executable, ...args].map(shellQuote).join(" ");
}

export function setupResultLine(result) {
    const status = result.status ?? (result.exitCode === 0 ? "ok" : "failed");
    return `[${status}] ${result.label ?? result.id}`;
}

function defaultReportPath() {
    return path.join(process.cwd(), `bundle-test-report-${new Date().toISOString().replaceAll(":", "-")}.json`);
}

export function timestamp() {
    return new Date().toISOString();
}

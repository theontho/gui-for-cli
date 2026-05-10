import { configValueKey, displayCommand, interpolate, missingPlaceholders } from "../shared/rendering.js";
import { runAction } from "../server/action-runner.js";
import { runSetup, setupEventLine } from "../server/setup-runner.js";
import { selectedItem } from "./rendering.js";
import type { TUIApp } from "./app.js";

export async function activateSelected(app: TUIApp) {
    const item = selectedItem(app.state);
    if (!item) {
        return;
    }
    switch (item.kind) {
        case "setup":
            await app.runSetupSteps();
            break;
        case "control":
            await app.editControl(item.control);
            break;
        case "configSetting":
            await app.editConfigSetting(item.control, item.setting);
            break;
        case "action":
            await app.runBundleAction(item.action, item.context);
            break;
    }
}

export async function editControl(app: TUIApp, control: Record<string, any>) {
    switch (control.kind) {
        case "text": {
            const value = await app.prompt(`${control.label ?? control.id}`, app.state.fieldValues?.[control.id] ?? control.value ?? "");
            await app.updateField(control, value);
            break;
        }
        case "path": {
            const value = await app.promptPath(`${control.label ?? control.id}`, app.state.fieldValues?.[control.id] ?? control.value ?? "");
            await app.updateField(control, value);
            break;
        }
        case "dropdown": {
            const option = await app.promptOption(control.label ?? control.id, control.options ?? [], app.state.fieldValues?.[control.id] ?? control.value);
            if (option) {
                await app.updateField(control, option.id);
            }
            break;
        }
        case "toggle":
            await app.updateField(control, app.state.fieldValues?.[control.id] === "true" ? "false" : "true");
            break;
        case "checkboxGroup": {
            const ids = await app.promptCheckboxes(control);
            await app.updateCheckedOptions(control, ids);
            break;
        }
        default:
            app.appendOutput("Info", `${control.label ?? control.id} is read-only in the TUI.`);
    }
    await app.refreshDataSources();
}

export async function editConfigSetting(app: TUIApp, control: Record<string, any>, setting: Record<string, any>) {
    const key = configValueKey(control, setting);
    if (setting.kind === "dropdown") {
        const option = await app.promptOption(setting.label ?? setting.id, setting.options ?? [], app.state.configValues?.[key] ?? setting.value);
        if (option) {
            await app.updateConfigSetting(control, setting, option.id);
        }
    } else if (setting.kind === "path") {
        const value = await app.promptPath(setting.label ?? setting.id, app.state.configValues?.[key] ?? setting.value ?? "");
        await app.updateConfigSetting(control, setting, value);
    } else {
        const value = await app.prompt(setting.label ?? setting.id, app.state.configValues?.[key] ?? setting.value ?? "");
        await app.updateConfigSetting(control, setting, value);
    }
    await app.refreshDataSources();
}

export async function runBundleAction(app: TUIApp, action: Record<string, any>, context: Record<string, any>) {
    const missing = missingPlaceholders(action.command ?? {}, context);
    if (missing.length) {
        app.appendOutput(action.title ?? action.id, `Missing required values: ${missing.join(", ")}`);
        return;
    }
    const confirmation = confirmationPrompt(action, context);
    if (confirmation) {
        const answer = await app.prompt(confirmation.prompt, "");
        if (!confirmation.matches(answer)) {
            app.appendOutput(action.title ?? action.id, "Cancelled.");
            return;
        }
    }
    const command = displayCommand(action.command, context);
    const entry = app.appendOutput(action.title ?? action.id, "Running...", command);
    app.render();
    try {
        const result = await runAction(action, context, new AbortController().signal, app.state.bundleRootPath, app.runProcess);
        entry.command = result.command ?? command;
        entry.body = [result.stdout, result.stderr, `exit ${result.exitCode}`].filter((part) => String(part ?? "").length > 0).join("\n");
        entry.kind = result.exitCode === 0 ? "success" : "error";
    } catch (error) {
        entry.kind = "error";
        entry.body = errorMessage(error);
    }
    app.state.dataSourcePayloads.clear();
    await app.refreshDataSources();
}

export async function runSetupSteps(app: TUIApp) {
    if (!(app.state.manifest?.setup?.steps ?? []).length) {
        app.appendOutput(app.state.labels?.setupTitle ?? "Setup", "No setup steps are defined.");
        return;
    }
    const entry = app.appendOutput(app.state.labels?.setupTitle ?? "Setup", "Running setup...");
    app.render();
    try {
        const setupRun = await runSetup(app.state.manifest, app.state.bundleRootPath, app.runProcess, (event) => {
            if (event.type === "step-start") {
                entry.body += `\n==> ${event.step.label}\n$ ${event.step.command}\n`;
            } else if (event.type === "output") {
                entry.body += event.text ?? "";
            } else {
                const line = setupEventLine(event);
                if (line) {
                    entry.body += `\n${line}`;
                }
            }
            app.render();
        });
        app.state.setupRun = { ...setupRun, completedAt: new Date().toISOString() };
        entry.kind = setupRun.status === "ok" ? "success" : "error";
        await app.persistBundleState({ setupRun: app.state.setupRun });
    } catch (error) {
        entry.kind = "error";
        entry.body += `\n${errorMessage(error)}`;
    } finally {
        await app.refreshDataSources();
    }
}

function confirmationPrompt(action: Record<string, any>, context: Record<string, any>) {
    const confirm = action.confirm;
    if (!confirm) {
        return undefined;
    }
    if (typeof confirm === "object") {
        const requiredText = interpolate(confirm.requiredText ?? "", context);
        const prompt = interpolate(
            confirm.prompt ?? (requiredText ? `Type "${requiredText}" to confirm.` : `Type yes to ${confirm.confirmButtonTitle ?? "continue"}.`),
            context,
        );
        return {
            prompt,
            matches: (answer: string) => requiredText ? answer === requiredText : answer.trim().toLowerCase() === "yes",
        };
    }
    return {
        prompt: `${String(confirm)}\nType yes to continue`,
        matches: (answer: string) => answer.trim().toLowerCase() === "yes",
    };
}

function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}

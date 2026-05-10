import { api } from "./api.js";
import { configValueKey } from "../shared/rendering.js";
import { clamp } from "./dom.js";
import { normalizeColorTheme, normalizeIconSet } from "./icons.js";
import { elements, errorMessage, findControl, resolveText } from "./model.js";
import { checkedOptionsChanged, configSettingChanged, fieldValueChanged, loadConfig, openBundleWorkspace, persistBundleState, runAction, runSetup, saveConfig } from "./operations.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { appendTerminal, closeTerminalTab, terminalTabs } from "./terminal.js";
import { bindTooltipEvents } from "./tooltips.js";
export { bindTooltipEvents } from "./tooltips.js";
const app = document.querySelector("#app") as any;
let terminalCopyFeedbackTimer = 0;
export function bindEvents(bootstrap) {
    bindTooltipEvents();
    bindSplitters();
    elements("[data-page-id]").forEach((button) => {
        button.addEventListener("click", async () => {
            state.activePageID = button.dataset.pageId;
            await persistBundleState();
            scheduleRender();
        });
    });
    elements("[data-locale-picker]").forEach((picker) => {
        picker.addEventListener("change", async (event) => {
            const target = event.currentTarget;
            state.dataSourcePayloads.clear();
            state.dataSourceErrors.clear();
            state.localizationCode = target.value;
            await persistBundleState();
            await bootstrap(target.value);
        });
    });
    app.querySelector("[data-icon-set-picker]")?.addEventListener("change", async (event) => {
        state.iconSet = normalizeIconSet(event.currentTarget.value);
        await persistBundleState();
        scheduleRender();
    });
    app.querySelector("[data-color-theme-picker]")?.addEventListener("change", async (event) => {
        state.colorTheme = normalizeColorTheme(event.currentTarget.value);
        await persistBundleState();
        scheduleRender();
    });
    app.querySelector("[data-web-font-picker]")?.addEventListener("change", async (event) => {
        state.webUIFont = event.currentTarget.value === "sfPro" ? "sfPro" : "system";
        await persistBundleState();
        scheduleRender();
    });
    app.querySelector("[data-run-setup]")?.addEventListener("click", async () => {
        await runSetup();
    });
    app.querySelector("[data-open-bundle-workspace]")?.addEventListener("click", async () => {
        await openBundleWorkspace();
    });
    elements("[data-field-id]").forEach((input) => {
        input.addEventListener("change", async () => {
            const control = findControl(input.dataset.fieldId);
            await fieldValueChanged(input.dataset.toggle != null ? String(input.checked) : input.value, control);
            state.dataSourcePayloads.clear();
            scheduleRender();
        });
    });
    elements("[data-path-prompt]").forEach((button) => {
        button.addEventListener("click", async (event) => {
            event.preventDefault();
            event.stopPropagation();
            const id = button.dataset.pathPrompt;
            const control = findControl(id);
            const value = await chooseLocalPath(control, state.fieldValues[id] ?? "");
            if (value) {
                await fieldValueChanged(value, control);
                state.dataSourcePayloads.clear();
                scheduleRender();
            }
        });
    });
    elements("[data-check-group]").forEach((input) => {
        input.addEventListener("change", async () => {
            const selected = state.checkedOptions[input.dataset.checkGroup] ?? new Set();
            input.checked ? selected.add(input.value) : selected.delete(input.value);
            await checkedOptionsChanged(selected, findControl(input.dataset.checkGroup));
            state.dataSourcePayloads.clear();
            scheduleRender();
        });
    });
    elements("[data-config-path]").forEach((input) => {
        input.addEventListener("change", async () => {
            state.configFilePaths[input.dataset.configPath] = input.value;
            await persistBundleState();
        });
    });
    elements("[data-config-control][data-config-setting]").forEach((input) => {
        input.addEventListener("change", async () => {
            const control = findControl(input.dataset.configControl);
            const setting = control.settings.find((candidate) => candidate.id === input.dataset.configSetting);
            const value = input.dataset.toggle != null ? String(input.checked) : input.value;
            await configSettingChanged(value, setting, control);
            state.dataSourcePayloads.clear();
            scheduleRender();
        });
    });
    elements("[data-config-path-prompt]").forEach((button) => {
        button.addEventListener("click", async (event) => {
            event.preventDefault();
            event.stopPropagation();
            const [controlID, settingID] = button.dataset.configPathPrompt.split(":");
            const control = findControl(controlID);
            const setting = control.settings.find((candidate) => candidate.id === settingID);
            const key = configValueKey(control, setting);
            const value = await chooseLocalPath(setting, state.configValues[key] ?? "");
            if (value) {
                await configSettingChanged(value, setting, control);
                state.dataSourcePayloads.clear();
                scheduleRender();
            }
        });
    });
    elements("[data-load-config]").forEach((button) => {
        button.addEventListener("click", async () => {
            await loadConfig(findControl(button.dataset.loadConfig));
            scheduleRender();
        });
    });
    elements("[data-save-config]").forEach((button) => {
        button.addEventListener("click", async () => {
            await saveConfig(findControl(button.dataset.saveConfig), true);
            scheduleRender();
        });
    });
    elements("[data-action-id]").forEach((button) => {
        button.addEventListener("click", async () => {
            let action;
            let context;
            try {
                action = JSON.parse(button.dataset.action ?? "");
                context = JSON.parse(button.dataset.actionContext ?? "");
            }
            catch (error) {
                const message = error instanceof Error ? error.message : String(error);
                console.error("Failed to parse action data:", error);
                appendTerminal("error", state.labels.terminalProcessErrorTitle, message);
                scheduleRender();
                return;
            }
            await runAction(action, context);
        });
    });
    elements("[data-terminal-tab]").forEach((button) => {
        button.addEventListener("click", () => {
            state.activeTerminalIndex = Number(button.dataset.terminalTab);
            scheduleRender();
        });
    });
    elements("[data-terminal-tab-close]").forEach((button) => {
        button.addEventListener("click", () => {
            closeTerminalTab(Number(button.dataset.terminalTabClose));
            scheduleRender();
        });
    });
    app.querySelector("[data-terminal-copy]")?.addEventListener("click", async () => {
        const entry = terminalTabs()[state.activeTerminalIndex] ?? terminalTabs()[0];
        await copyText(entry?.body ?? "");
        state.terminalCopyFeedback = true;
        window.clearTimeout(terminalCopyFeedbackTimer);
        terminalCopyFeedbackTimer = window.setTimeout(() => {
            state.terminalCopyFeedback = false;
            scheduleRender();
        }, 1600);
        scheduleRender();
    });
    app.querySelector("[data-terminal-toggle]")?.addEventListener("click", () => {
        state.isTerminalVisible = !state.isTerminalVisible;
        scheduleRender();
    });
    app.querySelector("[data-sidebar-toggle]")?.addEventListener("click", () => {
        state.isSidebarVisible = !state.isSidebarVisible;
        localStorage.setItem("guiForCLI.sidebarVisible", state.isSidebarVisible ? "true" : "false");
        scheduleRender();
    });
    elements("[data-retry-source]").forEach((button) => {
        button.addEventListener("click", () => {
            state.dataSourceErrors.delete(button.dataset.retrySource);
            scheduleRender();
        });
    });
    app.querySelector("[data-confirm-cancel]")?.addEventListener("click", () => {
        state.pendingConfirmation = null;
        scheduleRender();
    });
    app.querySelector("[data-confirm-input]")?.addEventListener("input", (event) => {
        const target = event.currentTarget;
        state.pendingConfirmation.input = target.value;
        const requiredText = resolveText(state.pendingConfirmation.action.confirm.requiredText ?? "", state.pendingConfirmation.context);
        const button = app.querySelector("[data-confirm-run]");
        if (button) {
            button.disabled = Boolean(requiredText && target.value !== requiredText);
        }
    });
    app.querySelector("[data-confirm-run]")?.addEventListener("click", async () => {
        const pending = state.pendingConfirmation;
        state.pendingConfirmation = null;
        await runAction({ ...pending.action, confirm: undefined }, pending.context);
    });
}
async function chooseLocalPath(spec, currentValue) {
    try {
        const result = await api("/api/path/pick", {
            method: "POST",
            body: {
                kind: pathPickerKind(spec),
                title: pathPickerTitle(spec),
                defaultPath: currentValue,
            },
        });
        return result.cancelled ? null : result.path;
    }
    catch (error) {
        appendTerminal("error", pathPickerTitle(spec), errorMessage(error));
        scheduleRender();
        return null;
    }
}
async function copyText(text) {
    if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        return;
    }
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.append(textarea);
    textarea.select();
    try {
        document.execCommand("copy");
    }
    finally {
        textarea.remove();
    }
}
function pathPickerTitle(spec) {
    return spec?.label ? `${state.labels.chooseButtonTitle} ${spec.label}` : state.labels.chooseButtonTitle;
}
function pathPickerKind(spec) {
    const explicitKind = String(spec?.pathType ?? spec?.pathKind ?? spec?.pathMode ?? "").toLowerCase();
    if (explicitKind === "directory" || explicitKind === "folder") {
        return "directory";
    }
    if (explicitKind === "file") {
        return "file";
    }
    const id = String(spec?.id ?? "").toLowerCase();
    const key = String(spec?.key ?? "").toLowerCase();
    const label = String(spec?.label ?? "").toLowerCase();
    const tooltip = String(spec?.tooltip ?? "").toLowerCase();
    const searchable = `${id} ${key} ${label} ${tooltip}`;
    if (id === "ref_path" || key === "reference_library") {
        return "directory";
    }
    if (/(^|[_\s-])(out|output)[_\s-]*(dir|directory)($|[_\s-])/.test(searchable) ||
        /(^|[_\s-])(dir|directory|folder|library|cache)($|[_\s-])/.test(searchable)) {
        return "directory";
    }
    return "file";
}
export function bindSplitters() {
    if (!state.isSidebarVisible) {
        return;
    }
    app.querySelector("[data-sidebar-resizer]")?.addEventListener("pointerdown", (event) => {
        const pointerEvent = event;
        event.preventDefault();
        const startX = pointerEvent.clientX;
        const startWidth = state.sidebarWidth;
        document.body.classList.add("resizing-sidebar");
        const move = (moveEvent) => {
            state.sidebarWidth = clamp(startWidth + moveEvent.clientX - startX, 160, 420);
            app.style.setProperty("--sidebar-width", `${state.sidebarWidth}px`);
        };
        const up = () => {
            localStorage.setItem("guiForCLI.sidebarWidth", String(Math.round(state.sidebarWidth)));
            document.body.classList.remove("resizing-sidebar");
            window.removeEventListener("pointermove", move);
            window.removeEventListener("pointerup", up);
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up, { once: true });
    });
    app.querySelector("[data-terminal-resizer]")?.addEventListener("pointerdown", (event) => {
        const pointerEvent = event;
        event.preventDefault();
        const startY = pointerEvent.clientY;
        const startHeight = state.terminalHeight;
        document.body.classList.add("resizing-terminal");
        const move = (moveEvent) => {
            state.terminalHeight = clamp(startHeight - (moveEvent.clientY - startY), 96, Math.max(96, window.innerHeight - 260));
            app.style.setProperty("--terminal-height", `${state.terminalHeight}px`);
        };
        const up = () => {
            localStorage.setItem("guiForCLI.terminalHeight", String(Math.round(state.terminalHeight)));
            document.body.classList.remove("resizing-terminal");
            window.removeEventListener("pointermove", move);
            window.removeEventListener("pointerup", up);
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up, { once: true });
    });
}

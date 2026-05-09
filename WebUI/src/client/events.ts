import { configValueKey } from "../shared/rendering.js";
import { clamp } from "./dom.js";
import { normalizeColorTheme, normalizeIconSet } from "./icons.js";
import { elements, findControl, resolveText } from "./model.js";
import { checkedOptionsChanged, configSettingChanged, fieldValueChanged, loadConfig, persistBundleState, runAction, saveConfig } from "./operations.js";
import { scheduleRender } from "./rerender.js";
import { state } from "./state.js";
import { closeTerminalTab } from "./terminal.js";
import { bindTooltipEvents } from "./tooltips.js";
export { bindTooltipEvents } from "./tooltips.js";
const app = document.querySelector("#app") as any;
export function bindEvents(bootstrap) {
    bindTooltipEvents();
    bindSplitters();
    elements("[data-page-id]").forEach((button) => {
        button.addEventListener("click", () => {
            state.activePageID = button.dataset.pageId;
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
    elements("[data-field-id]").forEach((input) => {
        input.addEventListener("change", async () => {
            const control = findControl(input.dataset.fieldId);
            await fieldValueChanged(input.dataset.toggle != null ? String(input.checked) : input.value, control);
            state.dataSourcePayloads.clear();
            scheduleRender();
        });
    });
    elements("[data-path-prompt]").forEach((button) => {
        button.addEventListener("click", async () => {
            const id = button.dataset.pathPrompt;
            const value = window.prompt(state.labels.chooseButtonTitle, state.fieldValues[id] ?? "");
            if (value != null) {
                await fieldValueChanged(value, findControl(id));
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
        button.addEventListener("click", async () => {
            const [controlID, settingID] = button.dataset.configPathPrompt.split(":");
            const control = findControl(controlID);
            const setting = control.settings.find((candidate) => candidate.id === settingID);
            const key = configValueKey(control, setting);
            const value = window.prompt(state.labels.chooseButtonTitle, state.configValues[key] ?? "");
            if (value != null) {
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
            const action = JSON.parse(button.dataset.action);
            const context = JSON.parse(button.dataset.actionContext);
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
    app.querySelector("[data-terminal-toggle]")?.addEventListener("click", () => {
        state.isTerminalVisible = !state.isTerminalVisible;
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
export function bindSplitters() {
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

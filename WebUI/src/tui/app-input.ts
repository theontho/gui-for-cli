import { stdout } from "node:process";
import { tuiItemsForPage } from "./rendering.js";
import type { TUIApp } from "./app.js";

export async function handleInput(app: TUIApp, data: string) {
    if (data === "\u0003" || data === "q") {
        app.close(data === "\u0003" ? 130 : 0);
        return;
    }
    if (data === "\t" || data === "\x1b[Z") {
        toggleFocusPane(app);
    } else if (data === "\x1b[A" || data === "k") {
        focusPane(app) === "terminal" ? scrollTerminal(app, 1) : moveSelection(app, -1);
    } else if (data === "\x1b[B" || data === "j") {
        focusPane(app) === "terminal" ? scrollTerminal(app, -1) : moveSelection(app, 1);
    } else if (data === "\x1b[5~" || data === "\u0015") {
        focusPane(app) === "terminal" ? scrollTerminal(app, 5) : moveSelection(app, -5);
    } else if (data === "\x1b[6~" || data === "\u0004") {
        focusPane(app) === "terminal" ? scrollTerminal(app, -5) : moveSelection(app, 5);
    } else if (data === "+" || data === "=") {
        resizeTerminal(app, 1);
    } else if (data === "-" || data === "_") {
        resizeTerminal(app, -1);
    } else if (data === "\x1b[D" || data === "h") {
        if (focusPane(app) === "terminal") {
            moveTerminalTab(app, -1);
        } else {
            app.state.focusPane = "main";
            await movePage(app, -1);
        }
    } else if (data === "\x1b[C" || data === "l") {
        if (focusPane(app) === "terminal") {
            moveTerminalTab(app, 1);
        } else {
            app.state.focusPane = "main";
            await movePage(app, 1);
        }
    } else if (data === "\r" || data === "\n") {
        if (focusPane(app) === "main") {
            await app.activateSelected();
        }
    } else if (data === "s") {
        await app.runSetupSteps();
    } else if (data === "r") {
        await app.refreshDataSources();
    } else if (data === "t") {
        cycleTheme(app);
    } else if (data === "x") {
        app.cancelActiveTerminalEntry();
    }
    if (app.running) {
        app.render();
    }
}

export function moveSelection(app: TUIApp, delta: number) {
    const count = tuiItemsForPage(app.state).length;
    app.state.selectedItemIndex = count ? (app.state.selectedItemIndex + delta + count) % count : 0;
}

export function toggleFocusPane(app: TUIApp) {
    app.state.focusPane = focusPane(app) === "terminal" ? "main" : "terminal";
}

export function focusPane(app: TUIApp) {
    return app.state.focusPane === "terminal" ? "terminal" : "main";
}

export function scrollTerminal(app: TUIApp, delta: number) {
    app.state.terminalScrollOffset = Math.max(0, (app.state.terminalScrollOffset ?? 0) + delta);
}

export function moveTerminalTab(app: TUIApp, delta: number) {
    const count = app.state.terminalEntries?.length ?? 0;
    if (!count) {
        return;
    }
    const rawIndex = Number(app.state.selectedTerminalEntryIndex);
    const current = Number.isFinite(rawIndex) ? rawIndex : count - 1;
    app.state.selectedTerminalEntryIndex = (current + delta + count) % count;
    app.state.terminalScrollOffset = 0;
}

export function resizeTerminal(app: TUIApp, delta: number) {
    const rows = stdout.rows || 32;
    const current = Number(app.state.terminalHeightRows || Math.floor(rows * 0.22) || 4);
    app.state.terminalHeightRows = Math.min(Math.max(2, current + delta), Math.max(2, rows - 12));
    app.fullRedraw = true;
}

export function cycleTheme(app: TUIApp) {
    const current = app.state.terminalTheme === "light" || app.state.terminalTheme === "dark" ? app.state.terminalTheme : "auto";
    app.state.terminalTheme = current === "auto" ? "dark" : current === "dark" ? "light" : "auto";
    app.fullRedraw = true;
}

export async function movePage(app: TUIApp, delta: number) {
    const pages = app.state.manifest?.pages ?? [];
    if (!pages.length) {
        return;
    }
    const current = Math.max(0, pages.findIndex((page) => page.id === app.state.activePageID));
    const next = (current + delta + pages.length) % pages.length;
    app.state.activePageID = pages[next].id;
    app.state.selectedItemIndex = 0;
    await app.persistBundleState({ selectedPageID: app.state.activePageID });
    await app.refreshDataSources();
}

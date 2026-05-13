import { execFileSync } from "node:child_process";
import type { TUIColorTheme } from "./rendering-format.js";

export type TUIThemePreference = "auto" | "dark" | "light";

type Env = Record<string, string | undefined>;
type SystemAppearanceReader = () => "dark" | "light" | undefined;
let cachedMacOSAppearance: { value: "dark" | "light" | undefined; readAt: number } | undefined;

export function resolveTerminalTheme(
    preference: TUIThemePreference | TUIColorTheme | undefined,
    env: Env = process.env,
    platform = process.platform,
    readSystemAppearance: SystemAppearanceReader = readMacOSAppearance,
): TUIColorTheme {
    if (preference === "dark" || preference === "light") {
        return preference;
    }
    return envTheme(env) ?? colorFgBgTheme(env.COLORFGBG) ?? terminalProfileTheme(env) ?? systemTheme(platform, readSystemAppearance) ?? "dark";
}

function envTheme(env: Env): TUIColorTheme | undefined {
    for (const key of ["GUI_FOR_CLI_TUI_THEME", "TERM_THEME", "TERMINAL_THEME", "COLOR_SCHEME"]) {
        const theme = namedTheme(env[key]);
        if (theme) {
            return theme;
        }
    }
    return undefined;
}

function terminalProfileTheme(env: Env): TUIColorTheme | undefined {
    for (const key of ["ITERM_PROFILE", "TERMINAL_PROFILE", "TERM_PROFILE", "ALACRITTY_THEME"]) {
        const theme = namedTheme(env[key]);
        if (theme) {
            return theme;
        }
    }
    return undefined;
}

function namedTheme(value: string | undefined): TUIColorTheme | undefined {
    const normalized = String(value ?? "").toLowerCase();
    if (normalized.includes("light")) {
        return "light";
    }
    if (normalized.includes("dark")) {
        return "dark";
    }
    return undefined;
}

function colorFgBgTheme(value: string | undefined): TUIColorTheme | undefined {
    const values = String(value ?? "").match(/\d{1,2}/g)?.map(Number) ?? [];
    const background = values.at(-1);
    if (background === undefined || !Number.isFinite(background)) {
        return undefined;
    }
    return background >= 7 && background <= 15 ? "light" : "dark";
}

function systemTheme(platform: string, readSystemAppearance: SystemAppearanceReader): TUIColorTheme | undefined {
    return platform === "darwin" ? readSystemAppearance() : undefined;
}

function readMacOSAppearance(): "dark" | "light" | undefined {
    const now = Date.now();
    if (cachedMacOSAppearance && now - cachedMacOSAppearance.readAt < 1_000) {
        return cachedMacOSAppearance.value;
    }
    try {
        const value = execFileSync("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"], {
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
            timeout: 200,
        }).trim().toLowerCase();
        cachedMacOSAppearance = { value: value === "dark" ? "dark" : "light", readAt: now };
        return cachedMacOSAppearance.value;
    } catch {
        cachedMacOSAppearance = { value: "light", readAt: now };
        return cachedMacOSAppearance.value;
    }
}

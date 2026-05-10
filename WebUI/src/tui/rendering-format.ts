export type TUIColorTheme = false | "dark" | "light";

const terminalControlSequence = /\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[PX^_][\s\S]*?\x1b\\|[@-Z\\-_])|[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g;
const sgrSequence = /^\x1b\[[0-9;]*m/;

export function frameTop(columns: number, title: string, color: TUIColorTheme) {
    const visibleTitle = ` ${stripANSI(title).trim()} `;
    const left = "╭";
    const right = "╮";
    const fill = Math.max(0, columns - visibleTitle.length - 2);
    return styleText(`${left}${"─".repeat(Math.floor(fill / 2))}${visibleTitle}${"─".repeat(Math.ceil(fill / 2))}${right}`, color, "border");
}

export function frameBottom(columns: number, color: TUIColorTheme) {
    return styleText(`╰${"─".repeat(columns - 2)}╯`, color, "border");
}

export function frameSeparator(columns: number, color: TUIColorTheme) {
    return styleText(`├${"─".repeat(columns - 2)}┤`, color, "border");
}

export function frameLine(content: string, columns: number, color: TUIColorTheme) {
    return `${styleText("│", color, "border")}${cell(content, columns - 2)}${styleText("│", color, "border")}`;
}

export function splitLine(left: string, right: string, leftWidth: number, rightWidth: number, color: TUIColorTheme) {
    return [
        styleText("│", color, "border"),
        cell(left, leftWidth),
        styleText("│", color, "separator"),
        cell(right, rightWidth),
        styleText("│", color, "border"),
    ].join("");
}

export function renderHelp(color: TUIColorTheme, themePreference = "auto") {
    return [
        keyCap("↑/↓", color),
        "move/scroll",
        keyCap("Tab", color),
        "focus",
        keyCap("+/-", color),
        "term size",
        keyCap("Pg", color),
        "jump",
        keyCap("←/→", color),
        "pages",
        keyCap("Enter", color),
        "edit/run",
        keyCap("s", color),
        "setup",
        keyCap("r", color),
        "refresh",
        keyCap("t", color),
        `theme:${themePreference}`,
        keyCap("q", color),
        "quit",
    ].join(" ");
}

export function cardHeader(title: string, columns: number, color: TUIColorTheme) {
    const label = ` ${title} `;
    const ruleWidth = Math.max(0, columns - visibleLength(label) - 2);
    return styleText(`┌${label}${"─".repeat(ruleWidth)}┐`, color, "border");
}

export function selectableLine(itemIndex: number, selected: number, content: string, columns: number, color: TUIColorTheme) {
    const focused = itemIndex === selected;
    const marker = focused ? styleText("›", color, "accent") : " ";
    const text = `${marker} ${content}`;
    return focused ? styleText(limit(text, columns), color, "focus") : limit(text, columns);
}

export function selectedPill(label: string, width: number, color: TUIColorTheme) {
    return styleText(limit(`› ${label}`, width), color, "focus");
}

export function fieldRow(label: string, value: string, color: TUIColorTheme) {
    const displayValue = value || "(empty)";
    return `${styleText(label, color, "strong")} ${styleText("=", color, "muted")} ${styleText(displayValue, color, value ? "value" : "muted")}`;
}

export function checkbox(checked: boolean, color: TUIColorTheme) {
    return checked ? styleText("[x] on", color, "success") : styleText("[ ] off", color, "muted");
}

export function actionButton(action: Record<string, any>, color: TUIColorTheme) {
    const role = action.role === "destructive" ? "danger" : action.role === "secondary" ? "buttonSecondary" : "button";
    return styleText(`[${action.title ?? action.id}]`, color, role);
}

export function statusBadge(status: string, color: TUIColorTheme) {
    const text = String(status ?? "info");
    const tone = statusTone(text);
    return styleText(`[${text}]`, color, tone);
}

export function statusPill(text: string, color: TUIColorTheme) {
    return styleText(`[${text}]`, color, "muted");
}

export function sidebarIcon(iconName: string) {
    const icons = {
        terminal: "▸",
        checklist: "☑",
        gearshape: "⚙",
        globe: "◉",
        folder: "▣",
        "folder.badge.gearshape": "▣",
        "doc.text": "□",
        "point.3.connected.trianglepath.dotted": "◇",
    };
    return icons[iconName] ?? "◦";
}

export function styleText(value: string, color: TUIColorTheme | boolean, role: string) {
    if (!color) {
        return value;
    }
    const codes = themeCodes(color === true ? "dark" : color);
    return `${codes[role] ?? ""}${value}\x1b[0m`;
}

export function wrap(value: any, columns: number) {
    const words = String(value ?? "").split(/\s+/).filter(Boolean);
    const lines: string[] = [];
    let line = "";
    for (const word of words) {
        if (!line) {
            line = word;
        } else if (line.length + word.length + 1 <= columns) {
            line += ` ${word}`;
        } else {
            lines.push(limit(line, columns));
            line = word;
        }
    }
    if (line) {
        lines.push(limit(line, columns));
    }
    return lines;
}

export function limit(value: any, columns: number) {
    const text = String(value ?? "");
    if (columns <= 0) {
        return "";
    }
    if (visibleLength(text) <= columns) {
        return sanitizePreservingSGR(text);
    }
    let output = "";
    let visible = 0;
    const suffix = columns >= 4 ? "..." : "";
    const target = columns - suffix.length;
    for (let index = 0; index < text.length;) {
        const remaining = text.slice(index);
        const sgr = sgrSequence.exec(remaining);
        if (sgr) {
            output += sgr[0];
            index += sgr[0].length;
            continue;
        }
        const control = terminalControlSequence.exec(remaining);
        terminalControlSequence.lastIndex = 0;
        if (control?.index === 0) {
            index += control[0].length;
            continue;
        }
        const character = Array.from(remaining)[0] ?? "";
        if (visible >= target) {
            break;
        }
        index += character.length;
        output += character;
        visible += 1;
    }
    return `${output}${output.includes("\x1b") ? "\x1b[0m" : ""}${suffix}`;
}

export function clamp(value: number, min: number, max: number) {
    return Math.min(max, Math.max(min, value));
}

export function ensureVisibleOffset(offset: number, index: number, height: number, maxOffset: number) {
    if (height <= 2) {
        if (index < offset) {
            return clamp(index, 0, maxOffset);
        }
        if (index >= offset + height) {
            return clamp(index - height + 1, 0, maxOffset);
        }
        return clamp(offset, 0, maxOffset);
    }
    if (index <= offset && offset > 0) {
        return clamp(index - 1, 0, maxOffset);
    }
    if (index >= offset + height - 1 && offset < maxOffset) {
        return clamp(index - height + 2, 0, maxOffset);
    }
    return clamp(offset, 0, maxOffset);
}

export function fillLines(lines: string[], height: number) {
    const output = lines.slice(0, height);
    while (output.length < height) {
        output.push("");
    }
    return output;
}

export function stripANSI(value: string) {
    return sanitizeTerminalText(value);
}

export function visibleLength(value: string) {
    return stripANSI(value).length;
}

function cell(content: string, width: number) {
    return padEndVisible(limit(` ${content}`, width), width);
}

function keyCap(label: string, color: TUIColorTheme) {
    return styleText(`[${label}]`, color, "key");
}

function statusTone(status: string) {
    switch (status.toLowerCase()) {
        case "ok":
        case "success":
        case "installed":
            return "success";
        case "warning":
        case "running":
        case "pending":
        case "unindexed":
        case "incomplete":
            return "warning";
        case "failed":
        case "error":
        case "missing":
            return "danger";
        default:
            return "muted";
    }
}

function padEndVisible(value: string, width: number) {
    return `${value}${" ".repeat(Math.max(0, width - visibleLength(value)))}`;
}

function sanitizeTerminalText(value: string) {
    return String(value ?? "").replace(terminalControlSequence, "");
}

function sanitizePreservingSGR(value: string) {
    const text = String(value ?? "");
    let output = "";
    for (let index = 0; index < text.length;) {
        const remaining = text.slice(index);
        const sgr = sgrSequence.exec(remaining);
        if (sgr) {
            output += sgr[0];
            index += sgr[0].length;
            continue;
        }
        const control = terminalControlSequence.exec(remaining);
        terminalControlSequence.lastIndex = 0;
        if (control?.index === 0) {
            index += control[0].length;
            continue;
        }
        const character = Array.from(remaining)[0] ?? "";
        output += character;
        index += character.length;
    }
    return output;
}

function themeCodes(theme: "dark" | "light"): Record<string, string> {
    if (theme === "light") {
        return {
            accent: "\x1b[38;5;25m",
            border: "\x1b[38;5;246m",
            button: "\x1b[1;38;5;255;48;5;25m",
            buttonSecondary: "\x1b[38;5;16;48;5;250m",
            code: "\x1b[38;5;236m",
            danger: "\x1b[38;5;160m",
            focus: "\x1b[1;38;5;16;48;5;153m",
            key: "\x1b[38;5;25m",
            muted: "\x1b[38;5;240m",
            section: "\x1b[1;38;5;25m",
            separator: "\x1b[38;5;250m",
            strong: "\x1b[1;38;5;16m",
            success: "\x1b[38;5;28m",
            title: "\x1b[1;38;5;16m",
            value: "\x1b[38;5;17m",
            warning: "\x1b[38;5;130m",
        };
    }
    return {
        accent: "\x1b[38;5;39m",
        border: "\x1b[38;5;240m",
        button: "\x1b[1;38;5;255;48;5;32m",
        buttonSecondary: "\x1b[38;5;255;48;5;238m",
        code: "\x1b[38;5;250m",
        danger: "\x1b[38;5;203m",
        focus: "\x1b[1;38;5;255;48;5;24m",
        key: "\x1b[38;5;110m",
        muted: "\x1b[38;5;245m",
        section: "\x1b[1;38;5;110m",
        separator: "\x1b[38;5;238m",
        strong: "\x1b[1;38;5;255m",
        success: "\x1b[38;5;77m",
        title: "\x1b[1;38;5;255m",
        value: "\x1b[38;5;231m",
        warning: "\x1b[38;5;214m",
    };
}

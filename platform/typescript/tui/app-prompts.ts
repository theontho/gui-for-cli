import { stdin, stdout } from "node:process";
import { createInterface } from "node:readline/promises";
import { optionCompleter, pathCompleter, resolveMultiOptionInput, resolveOptionInput } from "./completion.js";
import { optionTitle, selectedIDs } from "./rendering.js";
import type { TUIApp } from "./app.js";

export async function prompt(app: TUIApp, label: string, current: string, completer?: (line: string) => [string[], string]) {
    app.stopInput();
    stdout.write("\x1b[?25h\x1b[?1049l\n");
    const rl = createInterface({ input: stdin, output: stdout, completer });
    try {
        const answer = await rl.question(`${label}${current ? ` [${current}]` : ""}: `);
        return answer.length ? answer : current;
    } finally {
        rl.close();
        stdout.write("\x1b[?1049h");
        app.fullRedraw = true;
        app.startInput();
    }
}

export async function promptPath(app: TUIApp, label: string, current: string) {
    return prompt(app, `${label} (Tab completes paths)`, current, pathCompleter(app.state.bundleRootPath));
}

export async function promptOption(app: TUIApp, label: string, options: Record<string, any>[], current: string) {
    if (!options.length) {
        return undefined;
    }
    app.stopInput();
    stdout.write("\x1b[?25h\x1b[?1049l\n");
    const rl = createInterface({ input: stdin, output: stdout, completer: optionCompleter(options, app.state.labels) });
    stdout.write(`${label}\n`);
    options.forEach((option, index) => {
        const currentMarker = option.id === current ? "*" : " ";
        stdout.write(`  ${index + 1}. ${currentMarker} ${optionTitle(option, app.state.labels)}\n`);
    });
    try {
        const answer = await rl.question("Choose number, id, or title (Tab completes): ");
        return resolveOptionInput(answer, options, current, app.state.labels);
    } finally {
        rl.close();
        stdout.write("\x1b[?1049h");
        app.fullRedraw = true;
        app.startInput();
    }
}

export async function promptCheckboxes(app: TUIApp, control: Record<string, any>) {
    app.stopInput();
    stdout.write("\x1b[?25h\x1b[?1049l\n");
    const rl = createInterface({ input: stdin, output: stdout, completer: optionCompleter(control.options ?? [], app.state.labels) });
    const selected = new Set(selectedIDs(app.state.checkedOptions?.[control.id]));
    stdout.write(`${control.label ?? control.id}\n`);
    (control.options ?? []).forEach((option, index) => {
        const currentMarker = selected.has(option.id) ? "*" : " ";
        stdout.write(`  ${index + 1}. ${currentMarker} ${optionTitle(option, app.state.labels)}\n`);
    });
    try {
        const answer = await rl.question("Choose numbers, ids, or titles separated by commas (Tab completes, +/- patches): ");
        return resolveMultiOptionInput(answer, control.options ?? [], [...selected], app.state.labels);
    } finally {
        rl.close();
        stdout.write("\x1b[?1049h");
        app.fullRedraw = true;
        app.startInput();
    }
}

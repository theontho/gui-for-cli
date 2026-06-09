export function parseJsonWithComments<T = any>(source: string): T {
    return JSON.parse(stripJsonComments(source)) as T;
}

export function stripJsonComments(source: string): string {
    let output = "";
    let inString = false;
    let escaped = false;
    let inLineComment = false;
    let inBlockComment = false;

    for (let index = 0; index < source.length; index += 1) {
        const char = source[index] ?? "";
        const next = source[index + 1] ?? "";

        if (inLineComment) {
            if (char === "\n" || char === "\r") {
                inLineComment = false;
                output += char;
            } else {
                output += " ";
            }
            continue;
        }

        if (inBlockComment) {
            if (char === "*" && next === "/") {
                output += "  ";
                index += 1;
                inBlockComment = false;
            } else {
                output += char === "\n" || char === "\r" ? char : " ";
            }
            continue;
        }

        if (inString) {
            output += char;
            if (escaped) {
                escaped = false;
            } else if (char === "\\") {
                escaped = true;
            } else if (char === "\"") {
                inString = false;
            }
            continue;
        }

        if (char === "\"") {
            inString = true;
            output += char;
        } else if (char === "/" && next === "/") {
            output += "  ";
            index += 1;
            inLineComment = true;
        } else if (char === "/" && next === "*") {
            output += "  ";
            index += 1;
            inBlockComment = true;
        } else {
            output += char;
        }
    }

    return output;
}

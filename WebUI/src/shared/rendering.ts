const PLACEHOLDER_PATTERN = /\{\{([^}]+)\}\}/g;
export function initialFieldValues(manifest) {
    const values = {};
    for (const control of allControls(manifest)) {
        if (persistsFieldValue(control.kind)) {
            values[control.id] = control.value ?? values[control.id] ?? "";
        }
    }
    return values;
}
export function initialCheckedOptions(manifest) {
    const values = {};
    for (const control of allControls(manifest)) {
        if (control.kind === "checkboxGroup") {
            values[control.id] = new Set((control.options ?? []).filter((option) => option.selected).map((option) => option.id));
        }
    }
    return values;
}
export function initialConfigValues(manifest) {
    const values = {};
    for (const control of configEditorControls(manifest)) {
        for (const setting of control.settings ?? []) {
            values[configValueKey(control, setting)] = setting.value ?? "";
        }
    }
    return values;
}
export function configEditorControls(manifest) {
    return allControls(manifest).filter((control) => control.kind === "configEditor");
}
export function allControls(manifest) {
    return (manifest.pages ?? []).flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
}
export function configValueKey(control, setting) {
    return `${control.id}.${setting.id}`;
}
export function persistsFieldValue(kind) {
    return ["text", "path", "dropdown", "toggle"].includes(kind);
}
export function contextValue(context, placeholder) {
    if (placeholder === "bundleRoot" || placeholder === "bundleWorkspace") {
        return context.bundleRootPath;
    }
    if (placeholder === "home") {
        return context.homePath;
    }
    if (placeholder.startsWith("row.")) {
        return context.rowValues?.[placeholder.slice(4)];
    }
    if (placeholder.startsWith("config.")) {
        return context.configValues?.[placeholder.slice(7)];
    }
    const computed = computedFileStateValue(context, placeholder);
    if (computed != null) {
        return computed;
    }
    return (context.rowValues?.[placeholder] ??
        context.checkedOptions?.[placeholder] ??
        context.fieldValues?.[placeholder] ??
        context.configValues?.[placeholder]);
}
export function interpolate(value, context) {
    return String(value ?? "").replace(PLACEHOLDER_PATTERN, (_, rawPlaceholder) => {
        const placeholder = rawPlaceholder.trim();
        return contextValue(context, placeholder) ?? "";
    });
}
export function placeholdersIn(values) {
    const placeholders = [];
    for (const value of values) {
        for (const match of String(value ?? "").matchAll(PLACEHOLDER_PATTERN)) {
            const placeholder = match[1].trim();
            if (!placeholders.includes(placeholder)) {
                placeholders.push(placeholder);
            }
        }
    }
    return placeholders;
}
export function missingPlaceholders(command, context) {
    return placeholdersIn([command.executable, ...(command.arguments ?? [])]).filter((placeholder) => {
        const value = String(contextValue(context, placeholder) ?? "").trim();
        return value.length === 0;
    });
}
export function renderedCommand(command, context) {
    const optionalArguments = (command.optionalArguments ?? []).flatMap((group) => {
        if (missingRequiredPlaceholders(group, context).length > 0) {
            return [];
        }
        return group.map((argument) => interpolate(argument, context));
    });
    return {
        executable: interpolate(command.executable, context),
        arguments: [...(command.arguments ?? []).map((argument) => interpolate(argument, context)), ...optionalArguments],
    };
}
export function displayCommand(command, context) {
    const rendered = renderedCommand(command, context);
    return [rendered.executable, ...rendered.arguments].map(shellQuote).join(" ");
}
export function shellQuote(value) {
    const text = String(value ?? "");
    if (text && !/[\s\r\n]/.test(text) && !text.includes("'")) {
        return text;
    }
    return `'${text.replaceAll("'", "'\\''")}'`;
}
export function isActionVisible(action, context) {
    return (action.visibleWhen ?? []).every((condition) => conditionMatches(condition, context));
}
export function disabledReason(action, context, fallback = "This action is not available.") {
    if (!(action.disabledWhen ?? []).some((condition) => conditionMatches(condition, context))) {
        return undefined;
    }
    return action.disabledTooltip ? interpolate(action.disabledTooltip, context) : fallback;
}
export function conditionMatches(condition, context) {
    const rawValue = contextValue(context, condition.placeholder) ?? "";
    const value = String(rawValue).trim();
    if (condition.exists != null && condition.exists !== value.length > 0) {
        return false;
    }
    if (condition.equals != null && value !== interpolate(condition.equals, context)) {
        return false;
    }
    if (condition.notEquals != null && value === interpolate(condition.notEquals, context)) {
        return false;
    }
    if ((condition.in ?? []).length > 0 && !condition.in.map((item) => interpolate(item, context)).includes(value)) {
        return false;
    }
    if ((condition.notIn ?? []).map((item) => interpolate(item, context)).includes(value)) {
        return false;
    }
    if (condition.lessThan != null && !compareNumeric(value, interpolate(condition.lessThan, context), (left, right) => left < right)) {
        return false;
    }
    if (condition.lessThanOrEqual != null &&
        !compareNumeric(value, interpolate(condition.lessThanOrEqual, context), (left, right) => left <= right)) {
        return false;
    }
    if (condition.greaterThan != null &&
        !compareNumeric(value, interpolate(condition.greaterThan, context), (left, right) => left > right)) {
        return false;
    }
    if (condition.greaterThanOrEqual != null &&
        !compareNumeric(value, interpolate(condition.greaterThanOrEqual, context), (left, right) => left >= right)) {
        return false;
    }
    return true;
}
export function hydrateRows(control) {
    if (!(control.items ?? []).length) {
        return control.rows ?? [];
    }
    const template = control.rowTemplate ??
        {
            id: "{{id}}",
            title: "{{name}}",
            values: Object.fromEntries((control.columns ?? []).map((column) => [column.id, `{{${column.id}}}`])),
            status: "{{status}}",
            tags: [],
        };
    return (control.items ?? []).map((item, index) => {
        const values = item.values ?? item;
        const fallbackID = nonEmpty(values.id) ?? `row-${index + 1}`;
        const id = nonEmpty(interpolateItem(template.id, values)) ?? fallbackID;
        return {
            id,
            title: nonEmpty(template.title == null ? undefined : interpolateItem(template.title, values)),
            values: Object.fromEntries(Object.entries(template.values ?? {}).map(([key, value]) => [key, interpolateItem(value, values)])),
            status: nonEmpty(template.status == null ? undefined : interpolateItem(template.status, values)),
            tags: (template.tags ?? [])
                .map((tag) => ({
                ...tag,
                id: interpolateItem(tag.id, values),
                title: interpolateItem(tag.title, values),
            }))
                .filter((tag) => tag.title.trim()),
            tooltip: nonEmpty(template.tooltip == null ? undefined : interpolateItem(template.tooltip, values)),
        };
    });
}
export function rowContext(baseContext, row) {
    const rowValues = { ...(row.values ?? {}), id: row.id, title: row.title ?? row.id };
    if (row.status != null) {
        rowValues.status = row.status;
    }
    return { ...baseContext, rowValues };
}
export function checkedOptionsForContext(checkedOptions) {
    return Object.fromEntries(Object.entries(checkedOptions).map(([key, selected]) => [
        key,
        selected instanceof Set ? [...selected].sort().join(",") : [...(Array.isArray(selected) ? selected : [])].sort().join(","),
    ]));
}
export function applyDataSourcePayload(control, payload) {
    const next = structuredClone(control);
    if (payload.options) {
        next.options = payload.options;
    }
    if (payload.rows || payload.items) {
        next.rows = payload.rows ?? payload.items;
        next.items = [];
    }
    if (payload.rowActions || payload.actions) {
        next.rowActions = payload.rowActions ?? payload.actions;
    }
    return next;
}
export function serializeFlatToml(values) {
    return `${Object.entries(values)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, value]) => `${tomlKey(key)} = ${tomlValue(value)}`)
        .join("\n")}\n`;
}
export function parseFlatToml(text) {
    const values = {};
    for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#") || !line.includes("=")) {
            continue;
        }
        const [rawKey, ...rest] = line.split("=");
        const key = rawKey.trim().replace(/^"|"$/g, "");
        values[key] = parseTomlValue(rest.join("=").trim());
    }
    return values;
}
function interpolateItem(value, values) {
    return String(value ?? "").replace(PLACEHOLDER_PATTERN, (_, rawPlaceholder) => {
        const raw = rawPlaceholder.trim();
        const placeholder = raw.startsWith("item.") ? raw.slice(5) : raw;
        return values[placeholder] ?? "";
    });
}
function missingRequiredPlaceholders(values, context) {
    return placeholdersIn(values).filter((placeholder) => String(contextValue(context, placeholder) ?? "").trim().length === 0);
}
function computedFileStateValue(context, placeholder) {
    const separator = placeholder.lastIndexOf(".");
    if (separator <= 0 || separator >= placeholder.length - 1) {
        return undefined;
    }
    const fieldID = placeholder.slice(0, separator);
    const property = placeholder.slice(separator + 1);
    const rawPath = context.fieldValues?.[fieldID] ?? context.configValues?.[fieldID];
    switch (property) {
        case "pathExtension": {
            const name = String(rawPath ?? "").split(/[\\/]/).pop() ?? "";
            const dot = name.lastIndexOf(".");
            return dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
        }
        case "isIndexed":
        case "isSorted":
        case "exists":
            return "false";
        case "fileSize":
        case "fileSizeGB":
        case "parentDir":
            return "";
        default:
            return undefined;
    }
}
function compareNumeric(left, right, op) {
    const leftValue = evaluateNumeric(left);
    const rightValue = evaluateNumeric(right);
    return Number.isFinite(leftValue) && Number.isFinite(rightValue) && op(leftValue, rightValue);
}
export function evaluateNumeric(expression) {
    const parser = new NumericParser(String(expression ?? ""));
    return parser.parse();
}
class NumericParser {
    text;
    index;
    constructor(text) {
        this.text = text;
        this.index = 0;
    }
    parse() {
        const value = this.expression();
        this.skipWhitespace();
        return this.index === this.text.length ? value : Number.NaN;
    }
    expression() {
        let value = this.term();
        while (true) {
            this.skipWhitespace();
            if (this.consume("+")) {
                value += this.term();
            }
            else if (this.consume("-")) {
                value -= this.term();
            }
            else {
                return value;
            }
        }
    }
    term() {
        let value = this.factor();
        while (true) {
            this.skipWhitespace();
            if (this.consume("*")) {
                value *= this.factor();
            }
            else if (this.consume("/")) {
                value /= this.factor();
            }
            else {
                return value;
            }
        }
    }
    factor() {
        this.skipWhitespace();
        if (this.consume("+")) {
            return this.factor();
        }
        if (this.consume("-")) {
            return -this.factor();
        }
        if (this.consume("(")) {
            const value = this.expression();
            return this.consume(")") ? value : Number.NaN;
        }
        return this.number();
    }
    number() {
        this.skipWhitespace();
        const start = this.index;
        while (/[0-9.]/.test(this.text[this.index] ?? "")) {
            this.index += 1;
        }
        return start === this.index ? Number.NaN : Number(this.text.slice(start, this.index));
    }
    consume(token) {
        if (this.text[this.index] === token) {
            this.index += 1;
            return true;
        }
        return false;
    }
    skipWhitespace() {
        while (/\s/.test(this.text[this.index] ?? "")) {
            this.index += 1;
        }
    }
}
function tomlKey(key) {
    return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlValue(key);
}
function tomlValue(value) {
    return `"${String(value ?? "")
        .replaceAll("\\", "\\\\")
        .replaceAll('"', '\\"')
        .replaceAll("\n", "\\n")}"`;
}
function parseTomlValue(value) {
    if (!value.startsWith('"') || !value.endsWith('"')) {
        return value;
    }
    return value
        .slice(1, -1)
        .replace(/\\([nrt"\\])/g, (_, escaped) => ({ n: "\n", r: "\r", t: "\t", '"': '"', "\\": "\\" })[escaped] ?? escaped);
}
function nonEmpty(value) {
    const text = value == null ? "" : String(value);
    return text.length ? text : undefined;
}

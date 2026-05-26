import type {
    ActionSpec,
    BundleManifest,
    CommandContext,
    CommandSpec,
    ConditionSpec,
    ConfigSetting,
    ControlOption,
    ControlSpec,
    DataSourcePayload,
    Labels,
    LooseRecord,
    RowSpec,
    RowTagSpec,
    StateValue,
    StringMap,
    ValueMap,
} from "./types.js";

const PLACEHOLDER_PATTERN = /\{\{([^}]+)\}\}/g;

type CheckedOptionsInput = Record<string, Set<string> | string[] | string | null | undefined>;
type StateLike = {
    fieldValues?: ValueMap;
    checkedOptions?: CheckedOptionsInput;
    configValues?: ValueMap;
    bundleRootPath?: string;
    manifest?: BundleManifest | null;
    homePath?: string;
} & LooseRecord;

export function initialFieldValues(manifest: BundleManifest): ValueMap {
    const values: ValueMap = {};
    for (const control of allControls(manifest)) {
        if (persistsFieldValue(control.kind)) {
            values[control.id] = control.value ?? values[control.id] ?? "";
        }
    }
    return values;
}
export function initialCheckedOptions(manifest: BundleManifest): Record<string, Set<string>> {
    const values: Record<string, Set<string>> = {};
    for (const control of allControls(manifest)) {
        if (control.kind === "checkboxGroup") {
            values[control.id] = new Set((control.options ?? []).filter((option) => option.selected).map((option) => option.id));
        }
    }
    return values;
}
export function initialConfigValues(manifest: BundleManifest): ValueMap {
    const values: ValueMap = {};
    for (const control of configEditorControls(manifest)) {
        for (const setting of control.settings ?? []) {
            values[configValueKey(control, setting)] = setting.value ?? "";
        }
    }
    return values;
}
export function configEditorControls(manifest: Partial<BundleManifest> | LooseRecord): ControlSpec[] {
    return allControls(manifest).filter((control) => control.kind === "configEditor");
}
export function allControls(manifest: Partial<BundleManifest> | LooseRecord): ControlSpec[] {
    const pages = Array.isArray((manifest as Partial<BundleManifest>).pages) ? (manifest as Partial<BundleManifest>).pages : [];
    return pages.flatMap((page) => (page.sections ?? []).flatMap((section) => section.controls ?? []));
}
export function configValueKey(control: Pick<ControlSpec, "id"> | LooseRecord, setting: Pick<ConfigSetting, "id"> | LooseRecord): string {
    return `${String(control.id)}.${String(setting.id)}`;
}
export function commandContextFromState(state: StateLike, rowValues: ValueMap = {}, sectionValues: ValueMap = {}): CommandContext {
    const context: CommandContext = {
        fieldValues: { ...(state.fieldValues ?? {}), ...sectionValues },
        checkedOptions: checkedOptionsForContext(state.checkedOptions ?? {}),
        configValues: { ...(state.configValues ?? {}), ...(state.fieldValues ?? {}), ...sectionValues },
        rowValues,
        bundleRootPath: state.bundleRootPath,
        placeholderLabels: placeholderLabelsFromManifest(state.manifest),
    };
    if (state.homePath != null) {
        context.homePath = state.homePath;
    }
    return context;
}
function placeholderLabelsFromManifest(manifest: BundleManifest | null): Labels {
    const labels: Labels = {};
    for (const control of allControls(manifest ?? {})) {
        if (control.label) {
            labels[control.id] = control.label;
        }
        for (const setting of control.settings ?? []) {
            if (!setting.label) {
                continue;
            }
            labels[setting.id] = setting.label;
            if (setting.key) {
                labels[setting.key] = setting.label;
                labels[`${control.id}.${setting.key}`] = setting.label;
            }
            labels[`${control.id}.${setting.id}`] = setting.label;
        }
    }
    return labels;
}
export function persistsFieldValue(kind: string): boolean {
    return ["text", "path", "dropdown", "toggle"].includes(kind);
}
export function contextValue(context: CommandContext, placeholder: string): StateValue {
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
export function interpolate(value: unknown, context: CommandContext): string {
    return String(value ?? "").replace(PLACEHOLDER_PATTERN, (_, rawPlaceholder) => {
        const placeholder = rawPlaceholder.trim();
        return String(contextValue(context, placeholder) ?? "");
    });
}
export function placeholdersIn(values: unknown[]): string[] {
    const placeholders: string[] = [];
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
export function missingPlaceholders(command: CommandSpec, context: CommandContext): string[] {
    return placeholdersIn([command.executable, ...(command.arguments ?? [])]).filter((placeholder) => {
        const value = String(contextValue(context, placeholder) ?? "").trim();
        return value.length === 0;
    });
}
export function isPrecheckReady(precheck: LooseRecord | null | undefined, context: CommandContext): boolean {
    if (!precheck?.diskSpaceGB) {
        return false;
    }
    return placeholdersIn([precheck.diskSpaceGB])
        .filter((placeholder) => placeholder.endsWith(".fileSizeGB") || placeholder.endsWith(".fileSize"))
        .every((placeholder) => {
        const fieldID = placeholder.slice(0, placeholder.lastIndexOf("."));
        return String(context.fieldValues?.[fieldID] ?? context.configValues?.[fieldID] ?? "").trim().length > 0;
    });
}
export function renderedCommand(command: CommandSpec, context: CommandContext): CommandSpec {
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
export function displayCommand(command: CommandSpec, context: CommandContext): string {
    const rendered = renderedCommand(command, context);
    return [rendered.executable, ...rendered.arguments].map(shellQuote).join(" ");
}
export function setupResultLine(result: LooseRecord): string {
    const status = result.status ?? (result.exitCode === 0 ? "ok" : "failed");
    return `[${status}] ${result.label ?? result.id}`;
}
export function shellQuote(value: unknown): string {
    const text = String(value ?? "");
    if (/^[A-Za-z0-9_./-]+$/.test(text)) {
        return text;
    }
    return `'${text.replaceAll("'", "'\\''")}'`;
}
export function isActionVisible(action: ActionSpec, context: CommandContext): boolean {
    return (action.visibleWhen ?? []).every((condition) => conditionMatches(condition, context));
}
export function disabledReason(action: ActionSpec, context: CommandContext, fallback = "This action is not available."): string | undefined {
    if (!(action.disabledWhen ?? []).some((condition) => conditionMatches(condition, context))) {
        return undefined;
    }
    return action.disabledTooltip ? interpolate(action.disabledTooltip, context) : fallback;
}
export function conditionMatches(condition: ConditionSpec, context: CommandContext): boolean {
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
export function hydrateRows(control: ControlSpec | LooseRecord): RowSpec[] {
    const typedControl = control as ControlSpec;
    if (!(typedControl.items ?? []).length) {
        return typedControl.rows ?? [];
    }
    const template = typedControl.rowTemplate ??
        {
            id: "{{id}}",
            title: "{{name}}",
            values: Object.fromEntries((typedControl.columns ?? []).map((column) => [column.id, `{{${column.id}}}`])),
            status: "{{status}}",
            tags: [],
    };
    return (typedControl.items ?? []).map((item, index) => {
        const values = { ...item, ...objectRecord(item.values) } as ValueMap;
        const fallbackID = nonEmpty(values.id) ?? `row-${index + 1}`;
        const id = nonEmpty(interpolateItem(template.id, values)) ?? fallbackID;
        const title = template.title == null ? undefined : nonEmpty(interpolateItem(template.title, values));
        const status = template.status == null ? undefined : nonEmpty(interpolateItem(template.status, values));
        const tooltip = template.tooltip == null ? undefined : nonEmpty(interpolateItem(template.tooltip, values));
        const templateTags = (template.tags ?? [])
            .map((tag) => ({
            ...tag,
            id: interpolateItem(tag.id, values),
            title: interpolateItem(tag.title, values),
        }))
            .filter((tag) => tag.title.trim());
        return {
            id,
            title: title ?? nonEmpty(item.title),
            values: Object.fromEntries(Object.entries(template.values ?? {}).map(([key, value]) => [key, interpolateItem(value, values)])) as ValueMap,
            status: status ?? nonEmpty(item.status),
            tags: mergeTags(templateTags, arrayOfTags(item.tags)),
            tooltip: tooltip ?? nonEmpty(item.tooltip),
        };
    });
}
function mergeTags(first: RowTagSpec[], second: RowTagSpec[]): RowTagSpec[] {
    const seen = new Set();
    const tags: RowTagSpec[] = [];
    for (const tag of [...first, ...second]) {
        const key = `${tag.id ?? ""}\u0000${tag.title ?? ""}`;
        if (!String(tag.title ?? "").trim() || seen.has(key)) {
            continue;
        }
        seen.add(key);
        tags.push(tag);
    }
    return tags;
}
export function rowContext(baseContext: CommandContext, row: RowSpec): CommandContext {
    const rowValues: ValueMap = { ...(row.values ?? {}), id: row.id, title: row.title ?? row.id };
    if (row.status != null) {
        rowValues.status = row.status;
    }
    return { ...baseContext, rowValues };
}
export function checkedOptionsForContext(checkedOptions: CheckedOptionsInput): StringMap {
    return Object.fromEntries(Object.entries(checkedOptions).map(([key, selected]) => [
        key,
        selected instanceof Set || Array.isArray(selected)
            ? normalizeSelectedIDs(selected).sort().join(",")
            : selected == null
                ? ""
                : String(selected),
    ]));
}
export function normalizeSelectedIDs(value: Set<unknown> | unknown[] | unknown): string[] {
    if (value instanceof Set) {
        return [...value].map(String);
    }
    if (Array.isArray(value)) {
        return value.map(String);
    }
    return String(value ?? "")
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
}
export function optionTitle(option: ControlOption | RowSpec | LooseRecord, labels: Labels = {}): string {
    const status = option.status ? ` (${labels.libraryStatusLabels?.[String(option.status).toLowerCase()] ?? option.status})` : "";
    return `${option.title ?? option.id}${status}`;
}
export function applyDataSourcePayload(control: ControlSpec | LooseRecord, payload: DataSourcePayload): ControlSpec {
    const next = structuredClone(control) as ControlSpec;
    if (payload.options) {
        next.options = payload.options;
    }
    if (payload.rows) {
        next.rows = payload.rows;
        next.items = [];
    }
    if (payload.items) {
        next.items = payload.items;
    }
    if (payload.rowActions || payload.actions) {
        next.rowActions = payload.rowActions ?? payload.actions;
    }
    return next;
}
export function serializeFlatToml(values: Record<string, unknown>): string {
    return `${Object.entries(values)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, value]) => `${tomlKey(key)} = ${tomlValue(value)}`)
        .join("\n")}\n`;
}
export function parseFlatToml(text: string): StringMap {
    const values: StringMap = Object.create(null);
    for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim();
        if (!line || line.startsWith("#") || !line.includes("=")) {
            continue;
        }
        const separator = assignmentSeparator(line);
        if (separator < 0) {
            continue;
        }
        const rawKey = line.slice(0, separator).trim();
        const rawValue = line.slice(separator + 1).trim();
        const key = rawKey.startsWith('"') ? parseTomlValue(rawKey) : rawKey;
        values[key] = parseTomlValue(rawValue);
    }
    return values;
}
function assignmentSeparator(line: string): number {
    let inQuotes = false;
    let escaped = false;
    for (let index = 0; index < line.length; index += 1) {
        const character = line[index];
        if (escaped) {
            escaped = false;
            continue;
        }
        if (character === "\\" && inQuotes) {
            escaped = true;
            continue;
        }
        if (character === '"') {
            inQuotes = !inQuotes;
            continue;
        }
        if (character === "=" && !inQuotes) {
            return index;
        }
    }
    return -1;
}
function interpolateItem(value: unknown, values: ValueMap): string {
    return String(value ?? "").replace(PLACEHOLDER_PATTERN, (_, rawPlaceholder) => {
        const raw = rawPlaceholder.trim();
        const placeholder = raw.startsWith("item.") ? raw.slice(5) : raw;
        return String(values[placeholder] ?? "");
    });
}
function missingRequiredPlaceholders(values: unknown[], context: CommandContext): string[] {
    return placeholdersIn(values).filter((placeholder) => String(contextValue(context, placeholder) ?? "").trim().length === 0);
}
function computedFileStateValue(context: CommandContext, placeholder: string): StateValue {
    const separator = placeholder.lastIndexOf(".");
    if (separator <= 0 || separator >= placeholder.length - 1) {
        return undefined;
    }
    const fieldID = placeholder.slice(0, separator);
    const property = placeholder.slice(separator + 1);
    const rawPath = context.fieldValues?.[fieldID] ?? context.configValues?.[fieldID];
    const serverComputed = context.fileStateValues?.[placeholder];
    if (serverComputed != null) {
        return serverComputed;
    }
    switch (property) {
        case "pathExtension": {
            const name = String(rawPath ?? "").split(/[\\/]/).pop() ?? "";
            const dot = name.lastIndexOf(".");
            return dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
        }
        default:
            return undefined;
    }
}
function compareNumeric(left: unknown, right: unknown, op: (left: number, right: number) => boolean): boolean {
    const leftValue = evaluateNumeric(left);
    const rightValue = evaluateNumeric(right);
    return Number.isFinite(leftValue) && Number.isFinite(rightValue) && op(leftValue, rightValue);
}
export function evaluateNumeric(expression: unknown): number {
    const parser = new NumericParser(String(expression ?? ""));
    return parser.parse();
}
class NumericParser {
    text: string;
    index: number;
    constructor(text: string) {
        this.text = text;
        this.index = 0;
    }
    parse(): number {
        const value = this.expression();
        this.skipWhitespace();
        return this.index === this.text.length ? value : Number.NaN;
    }
    expression(): number {
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
    term(): number {
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
    factor(): number {
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
    number(): number {
        this.skipWhitespace();
        const start = this.index;
        while (/[0-9.]/.test(this.text[this.index] ?? "")) {
            this.index += 1;
        }
        return start === this.index ? Number.NaN : Number(this.text.slice(start, this.index));
    }
    consume(token: string): boolean {
        if (this.text[this.index] === token) {
            this.index += 1;
            return true;
        }
        return false;
    }
    skipWhitespace(): void {
        while (/\s/.test(this.text[this.index] ?? "")) {
            this.index += 1;
        }
    }
}
function tomlKey(key: string): string {
    return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlValue(key);
}
function tomlValue(value: unknown): string {
    return `"${String(value ?? "")
        .replaceAll("\\", "\\\\")
        .replaceAll('"', '\\"')
        .replaceAll("\n", "\\n")}"`;
}
function parseTomlValue(value: string): string {
    if (!value.startsWith('"') || !value.endsWith('"')) {
        return value;
    }
    return value
        .slice(1, -1)
        .replace(/\\([nrt"\\])/g, (_, escaped) => ({ n: "\n", r: "\r", t: "\t", '"': '"', "\\": "\\" })[escaped] ?? escaped);
}
function nonEmpty(value: unknown): string | undefined {
    const text = value == null ? "" : String(value);
    return text.length ? text : undefined;
}

function objectRecord(value: unknown): LooseRecord {
    return value != null && typeof value === "object" && !Array.isArray(value) ? value as LooseRecord : {};
}

function arrayOfTags(value: unknown): RowTagSpec[] {
    return Array.isArray(value) ? value.filter((item): item is RowTagSpec => item != null && typeof item === "object") : [];
}

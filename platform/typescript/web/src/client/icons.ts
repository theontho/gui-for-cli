export function normalizeIconSet(value) {
    return value === "emoji" ? "emoji" : "platform";
}
export function normalizeColorTheme(value) {
    return value === "light" || value === "dark" ? value : "system";
}

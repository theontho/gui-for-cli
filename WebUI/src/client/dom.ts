export function escapeHTML(value) {
    return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character] ?? character);
}
export function escapeAttribute(value) {
    return escapeHTML(value);
}
export function clamp(value, minimum, maximum) {
    return Math.min(Math.max(value, minimum), maximum);
}

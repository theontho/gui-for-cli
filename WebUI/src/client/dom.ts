export function escapeHTML(value) {
    return String(value ?? "").replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character] ?? character);
}
export function escapeAttribute(value) {
    return escapeHTML(value);
}
export function clamp(value, minimum, maximum) {
    return Math.min(Math.max(value, minimum), maximum);
}

export function resizedSidebarWidth(startWidth, startX, currentX, direction) {
    const delta = currentX - startX;
    const directionMultiplier = direction === "rtl" ? -1 : 1;
    return clamp(startWidth + delta * directionMultiplier, 160, 420);
}

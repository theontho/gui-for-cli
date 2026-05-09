let _render = () => { };
export function setRender(fn) {
    _render = fn;
}
export function scheduleRender() {
    _render();
}

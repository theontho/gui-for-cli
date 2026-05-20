const DEFAULT_TEXT_ZOOM = 1;
const MIN_TEXT_ZOOM = 0.7;
const MAX_TEXT_ZOOM = 2;
const TEXT_ZOOM_STEP = 0.1;

declare global {
  var __GUI_FOR_CLI_TAURI__: boolean | undefined;
}

export interface TextZoomKeyboardEvent {
  key?: string;
  code?: string;
  metaKey?: boolean;
  ctrlKey?: boolean;
  altKey?: boolean;
  shiftKey?: boolean;
  defaultPrevented?: boolean;
}

export type TextZoomAction = "in" | "out" | "reset";

export function isTextZoomAction(value: unknown): value is TextZoomAction {
  return value === "in" || value === "out" || value === "reset";
}

export function normalizeTextZoom(value: unknown) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return DEFAULT_TEXT_ZOOM;
  }
  return clampTextZoom(value);
}

export function nextTextZoom(currentZoom: unknown, action: TextZoomAction) {
  const current = normalizeTextZoom(currentZoom);
  if (action === "reset") {
    return DEFAULT_TEXT_ZOOM;
  }
  const delta = action === "in" ? TEXT_ZOOM_STEP : -TEXT_ZOOM_STEP;
  return clampTextZoom(roundTextZoom(current + delta));
}

export function applyTextZoom(
  textZoom: unknown,
  root: Pick<CSSStyleDeclaration, "fontSize"> = document.documentElement.style
) {
  const zoom = normalizeTextZoom(textZoom);
  root.fontSize = zoom === DEFAULT_TEXT_ZOOM ? "" : `${Math.round(zoom * 100)}%`;
}

export function textZoomActionForKeyboardEvent(
  event: TextZoomKeyboardEvent
): TextZoomAction | null {
  if (event.defaultPrevented || event.altKey || (!event.metaKey && !event.ctrlKey)) {
    return null;
  }
  if (event.key === "0" || event.code === "Digit0" || event.code === "Numpad0") {
    return "reset";
  }
  if (
    event.key === "+" ||
    event.key === "=" ||
    event.code === "Equal" ||
    event.code === "NumpadAdd"
  ) {
    return "in";
  }
  if (
    event.key === "-" ||
    event.key === "_" ||
    event.code === "Minus" ||
    event.code === "NumpadSubtract"
  ) {
    return "out";
  }
  return null;
}

export function isTauriShell(globalScope: typeof globalThis = globalThis) {
  return globalScope.__GUI_FOR_CLI_TAURI__ === true;
}

function clampTextZoom(value: number) {
  return Math.min(MAX_TEXT_ZOOM, Math.max(MIN_TEXT_ZOOM, roundTextZoom(value)));
}

function roundTextZoom(value: number) {
  return Math.round(value * 10) / 10;
}

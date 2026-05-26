import { commandContextFromState, interpolate } from "../../../shared/rendering.js";
import type { ControlSpec, WebUIState } from "../../../shared/types.js";

export function pathPickerDefaultPath(spec: ControlSpec | undefined, currentValue: unknown, state: WebUIState) {
    const currentPath = String(currentValue ?? "").trim();
    if (currentPath) {
        return currentPath;
    }
    const defaultDirectory = String(spec?.defaultDirectory ?? "").trim();
    return defaultDirectory ? interpolate(defaultDirectory, commandContextFromState(state)) : "";
}

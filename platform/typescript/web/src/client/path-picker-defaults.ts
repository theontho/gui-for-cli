import { commandContextFromState, interpolate } from "../../../shared/rendering.js";

export function pathPickerDefaultPath(spec: Record<string, any> | undefined, currentValue: unknown, state: Record<string, any>) {
    const currentPath = String(currentValue ?? "").trim();
    if (currentPath) {
        return currentPath;
    }
    const defaultDirectory = String(spec?.defaultDirectory ?? "").trim();
    return defaultDirectory ? interpolate(defaultDirectory, commandContextFromState(state)) : "";
}

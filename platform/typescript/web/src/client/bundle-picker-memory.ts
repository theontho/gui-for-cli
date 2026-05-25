const bundlePickerLastDirectoryKey = "guiForCLI.bundlePicker.lastDirectory";

export function bundlePickerDefaultPath(fallbackPath = "", storage = globalThis.localStorage) {
    return storage?.getItem(bundlePickerLastDirectoryKey) || fallbackPath;
}

export function rememberBundlePickerPath(selectedPath, storage = globalThis.localStorage) {
    const directory = parentDirectory(String(selectedPath ?? "").trim());
    if (directory) {
        storage?.setItem(bundlePickerLastDirectoryKey, directory);
    }
}

export function parentDirectory(rawPath) {
    const value = String(rawPath ?? "").trim().replace(/[\\/]+$/, "");
    if (!value) {
        return "";
    }
    const separator = Math.max(value.lastIndexOf("/"), value.lastIndexOf("\\"));
    if (separator < 0) {
        return "";
    }
    if (separator === 0) {
        return value.slice(0, 1);
    }
    if (/^[A-Za-z]:[\\/]?$/.test(value.slice(0, separator + 1))) {
        return value.slice(0, separator + 1);
    }
    return value.slice(0, separator);
}

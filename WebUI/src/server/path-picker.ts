import { execFile } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { homedir, platform } from "node:os";
import path from "node:path";

const macOSPickerScript = `
on run argv
  set pickerKind to item 1 of argv
  set dialogTitle to item 2 of argv
  set defaultPath to item 3 of argv

  if defaultPath is not "" then
    set defaultLocation to POSIX file defaultPath as alias
    if pickerKind is "directory" then
      set chosenItem to choose folder with prompt dialogTitle default location defaultLocation
    else
      set chosenItem to choose file with prompt dialogTitle default location defaultLocation
    end if
  else
    if pickerKind is "directory" then
      set chosenItem to choose folder with prompt dialogTitle
    else
      set chosenItem to choose file with prompt dialogTitle
    end if
  end if

  return POSIX path of chosenItem
end run
`;

export async function pickPath(options: Record<string, any> = {}) {
    const kind = normalizePathPickerKind(options.kind);
    if (platform() !== "darwin") {
        throw new Error("Native file and directory picking is currently available only on macOS.");
    }
    const title = String(options.title || (kind === "directory" ? "Choose directory" : "Choose file"));
    const defaultLocation = defaultLocationForPath(options.defaultPath, options.bundleRoot);
    const result = await runMacOSPicker(kind, title, defaultLocation);
    return result ? { path: result, kind, cancelled: false } : { kind, cancelled: true };
}

function normalizePathPickerKind(value) {
    if (value === "directory" || value === "folder") {
        return "directory";
    }
    if (value === "file") {
        return "file";
    }
    throw new Error("Path picker kind must be file or directory.");
}

async function runMacOSPicker(kind, title, defaultLocation) {
    return new Promise((resolve, reject) => {
        execFile("/usr/bin/osascript", ["-e", macOSPickerScript, kind, title, defaultLocation], { encoding: "utf8" }, (error, stdout, stderr) => {
            if (!error) {
                resolve(stdout.trim());
                return;
            }
            if (isUserCancelled(error, stderr)) {
                resolve(null);
                return;
            }
            reject(new Error(stderr.trim() || error.message));
        });
    });
}

function isUserCancelled(error, stderr) {
    return error?.code === 1 && /User canceled|User cancelled/i.test(stderr ?? "");
}

function defaultLocationForPath(rawPath, bundleRoot) {
    const candidate = normalizeDefaultPath(rawPath, bundleRoot);
    if (!candidate) {
        return existingDirectory(bundleRoot) ?? "";
    }
    const exactDirectory = existingDirectory(candidate);
    if (exactDirectory) {
        return exactDirectory;
    }
    const exactParent = existingParentDirectory(candidate);
    if (exactParent) {
        return exactParent;
    }
    return existingDirectory(bundleRoot) ?? "";
}

function normalizeDefaultPath(rawPath, bundleRoot) {
    const value = typeof rawPath === "string" ? rawPath.trim() : "";
    if (!value) {
        return "";
    }
    const expanded = value === "~" ? homedir() : value.startsWith("~/") ? path.join(homedir(), value.slice(2)) : value;
    return path.isAbsolute(expanded) ? expanded : path.resolve(bundleRoot || process.cwd(), expanded);
}

function existingParentDirectory(candidate) {
    let current = path.dirname(candidate);
    while (current && current !== path.dirname(current)) {
        const directory = existingDirectory(current);
        if (directory) {
            return directory;
        }
        current = path.dirname(current);
    }
    return existingDirectory(current);
}

function existingDirectory(candidate) {
    if (typeof candidate !== "string" || !candidate || !existsSync(candidate)) {
        return undefined;
    }
    const info = statSync(candidate);
    if (info.isDirectory()) {
        return candidate;
    }
    if (info.isFile()) {
        return path.dirname(candidate);
    }
    return undefined;
}

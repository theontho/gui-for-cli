#!/usr/bin/env python3
import argparse
import pathlib
import re


PATH_PICKER_CHANNEL = """\

    let pathPickerChannel = FlutterMethodChannel(
      name: "gui_for_cli/path_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    pathPickerChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "openPath" {
        let arguments = call.arguments as? [String: Any]
        let path = arguments?["path"] as? String ?? ""
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        result(nil)
        return
      }
      guard call.method == "pickPath" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let kind = arguments?["kind"] as? String ?? "file"
      let panel = NSOpenPanel()
      panel.canChooseFiles = kind != "directory"
      panel.canChooseDirectories = kind == "directory"
      panel.allowsMultipleSelection = false
      let finish: (NSApplication.ModalResponse) -> Void = { response in
        result(response == .OK ? panel.url?.path : nil)
      }
      if let window = self {
        panel.beginSheetModal(for: window, completionHandler: finish)
      } else {
        finish(panel.runModal())
      }
    }
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Set the generated Flutter macOS window size.")
    parser.add_argument("main_window", type=pathlib.Path)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        parser.error("width and height must be positive integers")

    source = args.main_window.read_text()
    new = (
        f"    let windowFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, "
        f"width: {args.width}, height: {args.height})\n"
    )
    generated = "    let windowFrame = self.frame\n"
    configured = re.compile(
        r"    let windowFrame = NSRect\(x: self\.frame\.origin\.x, y: self\.frame\.origin\.y, "
        r"width: \d+, height: \d+\)\n"
    )
    if generated in source:
        source = source.replace(generated, new, 1)
    elif configured.search(source):
        source = configured.sub(new, source, count=1)
    else:
        raise RuntimeError(f"Could not find generated windowFrame line in {args.main_window}")
    if "FlutterMethodChannel(\n      name: \"gui_for_cli/path_picker\"" not in source:
        plugin_registration = "    RegisterGeneratedPlugins(registry: flutterViewController)\n"
        if plugin_registration not in source:
            raise RuntimeError(
                f"Could not find generated plugin registration line in {args.main_window}"
            )
        source = source.replace(
            plugin_registration, plugin_registration + PATH_PICKER_CHANNEL, 1
        )
    args.main_window.write_text(source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
